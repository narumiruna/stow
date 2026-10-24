mod no_clipboard;

use iced::widget::{button, column, container, row, scrollable, text, text_input};
use iced::{Element, Length};

fn main() -> iced::Result {
    iced::application(Probe::default, Probe::update, Probe::view)
        .title("Stow iced feasibility probe — not a production app")
        .window_size((960.0, 640.0))
        .run()
}

#[derive(Debug)]
struct Item {
    id: u32,
    title: &'static str,
    content: &'static str,
    kind: &'static str,
}

#[derive(Debug, Clone)]
enum Message {
    Search(String),
    Select(u32),
    Edit(String),
    FailSave,
}

struct Probe {
    items: Vec<Item>,
    query: String,
    selection: Option<u32>,
    draft: String,
    status: &'static str,
}

impl Default for Probe {
    fn default() -> Self {
        Self {
            items: vec![
                Item {
                    id: 1,
                    title: "Welcome note",
                    content: "Edit this in-memory sample with the keyboard.",
                    kind: "Text",
                },
                Item {
                    id: 2,
                    title: "Rust snippet",
                    content: "fn main() { /* sample only */ }",
                    kind: "Code",
                },
                Item {
                    id: 3,
                    title: "Reference link",
                    content: "https://example.invalid — display text only",
                    kind: "Link",
                },
            ],
            query: String::new(),
            selection: Some(1),
            draft: "Edit this in-memory sample with the keyboard.".into(),
            status: "Sample data only. Nothing is saved.",
        }
    }
}

impl Probe {
    fn matches(&self, item: &Item) -> bool {
        let query = self.query.trim().to_lowercase();
        [item.title, item.content, item.kind]
            .iter()
            .any(|value| value.to_lowercase().contains(&query))
    }

    fn visible_items(&self) -> impl Iterator<Item = &Item> {
        self.items.iter().filter(|item| self.matches(item))
    }

    fn selected_item(&self) -> Option<&Item> {
        self.visible_items()
            .find(|item| Some(item.id) == self.selection)
    }

    fn update(&mut self, message: Message) {
        match message {
            Message::Search(query) => self.query = query,
            Message::Select(id) => {
                let content = self
                    .visible_items()
                    .find(|item| item.id == id)
                    .map(|item| item.content.to_owned());
                if let Some(content) = content
                    && self.selection != Some(id)
                {
                    self.selection = Some(id);
                    self.draft = content;
                    self.status = "Sample selected. Nothing is saved.";
                }
            }
            Message::Edit(draft) => {
                if self.selected_item().is_some() {
                    self.draft = draft;
                    self.status = "Unsaved in-memory draft.";
                }
            }
            Message::FailSave => {
                self.status = if self.selected_item().is_some() {
                    "Simulated save failure. Draft retained; nothing was written."
                } else {
                    "Save rejected: selection is no longer in the results. Draft retained."
                };
            }
        }
    }

    fn view(&self) -> Element<'_, Message> {
        let mut list = column![text("Library (sample)").size(24)].spacing(8);
        let mut count = 0;
        for item in self.visible_items() {
            count += 1;
            let label = format!(
                "{}{} [{}]",
                if self.selection == Some(item.id) {
                    "> "
                } else {
                    ""
                },
                item.title,
                item.kind
            );
            list = list.push(
                button(text(label))
                    .on_press(Message::Select(item.id))
                    .width(Length::Fill),
            );
        }
        if count == 0 {
            list = list.push(text("No matching sample items."));
        }

        let details: Element<'_, Message> = if let Some(item) = self.selected_item() {
            column![
                text("Details").size(24),
                text(item.title),
                text(format!(
                    "Type: {} · In-memory sample #{}",
                    item.kind, item.id
                )),
                text("Content (single line; keyboard editable)"),
                text_input("Draft content", &self.draft).on_input(Message::Edit),
                button("Simulate failed save").on_press(Message::FailSave),
                text("Selecting another item replaces this sample draft."),
            ]
            .spacing(12)
            .into()
        } else {
            column![
                text("No valid selection").size(24),
                text("Select a visible item. A hidden selection cannot be edited or saved."),
                text("The previous draft remains in memory until another item is selected."),
            ]
            .spacing(12)
            .into()
        };

        no_clipboard::wrap(
            container(
                column![
                    text("Phase 0 iced probe — NOT a production app").size(24),
                    text("Local-only sample · RAM only · No storage or sync · Clipboard disabled"),
                    text_input("Search sample title, content, or type", &self.query)
                        .on_input(Message::Search),
                    row![
                        scrollable(list).width(Length::FillPortion(2)),
                        container(details).width(Length::FillPortion(3)).padding(12),
                    ]
                    .spacing(16)
                    .height(Length::Fill),
                    text(self.status),
                ]
                .spacing(16),
            )
            .padding(20)
            .into(),
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn filtering_matches_title_content_and_kind_without_case_or_outer_spaces() {
        let mut probe = Probe::default();
        for (query, expected) in [
            (" RUST ", vec![2]),
            ("example.invalid", vec![3]),
            ("TEXT", vec![1, 3]),
            ("CODE", vec![2]),
            ("missing", vec![]),
            ("", vec![1, 2, 3]),
        ] {
            probe.update(Message::Search(query.into()));
            assert_eq!(
                probe
                    .visible_items()
                    .map(|item| item.id)
                    .collect::<Vec<_>>(),
                expected
            );
        }
    }

    #[test]
    fn stale_hidden_selection_rejects_edit_save_and_selection_messages() {
        let mut probe = Probe::default();
        let draft = probe.draft.clone();
        probe.update(Message::Search("Rust".into()));
        assert!(probe.selected_item().is_none());
        probe.update(Message::Edit("must not apply".into()));
        probe.update(Message::Select(1));
        probe.update(Message::Select(999));
        probe.update(Message::FailSave);
        assert_eq!(probe.selection, Some(1));
        assert_eq!(probe.draft, draft);
        assert!(probe.status.starts_with("Save rejected"));
        probe.update(Message::Search(String::new()));
        assert_eq!(probe.selected_item().unwrap().id, 1);
    }

    #[test]
    fn removed_selection_cannot_save() {
        let mut probe = Probe::default();
        probe.items.retain(|item| item.id != 1);
        probe.update(Message::FailSave);
        assert!(probe.selected_item().is_none());
        assert!(probe.status.starts_with("Save rejected"));
    }

    #[test]
    fn failed_save_preserves_draft_and_original_item() {
        let mut probe = Probe::default();
        let original = probe.selected_item().unwrap().content;
        probe.update(Message::Edit("unsaved 日本語 draft".into()));
        probe.update(Message::FailSave);
        probe.update(Message::FailSave);
        assert_eq!(probe.draft, "unsaved 日本語 draft");
        assert_eq!(probe.selected_item().unwrap().content, original);
        assert!(probe.status.starts_with("Simulated save failure"));
        probe.update(Message::Select(1));
        assert_eq!(probe.draft, "unsaved 日本語 draft");
        probe.update(Message::Edit("retry draft".into()));
        assert_eq!(probe.draft, "retry draft");
    }

    #[test]
    fn visible_selection_loads_its_sample_content() {
        let mut probe = Probe::default();
        probe.update(Message::Select(2));
        assert_eq!(probe.selected_item().unwrap().id, 2);
        assert_eq!(probe.draft, probe.selected_item().unwrap().content);
    }
}
