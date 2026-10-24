//! Keep editable widgets from reading or writing the system clipboard.
//! This wrapper supports only the probe's widgets, which have no overlays.
use iced::advanced::{
    Clipboard, Layout, Shell, Widget, clipboard, layout, mouse, renderer, widget,
};
use iced::{Element, Event, Length, Rectangle, Renderer, Size, Theme};

pub fn wrap<'a, Message: 'a>(content: Element<'a, Message>) -> Element<'a, Message> {
    Element::new(NoClipboard(content))
}

struct NoClipboard<'a, Message>(Element<'a, Message>);

impl<Message> Widget<Message, Theme, Renderer> for NoClipboard<'_, Message> {
    fn size(&self) -> Size<Length> {
        self.0.as_widget().size()
    }

    fn tag(&self) -> widget::tree::Tag {
        self.0.as_widget().tag()
    }

    fn state(&self) -> widget::tree::State {
        self.0.as_widget().state()
    }

    fn children(&self) -> Vec<widget::Tree> {
        self.0.as_widget().children()
    }

    fn diff(&self, tree: &mut widget::Tree) {
        self.0.as_widget().diff(tree);
    }

    fn layout(
        &mut self,
        tree: &mut widget::Tree,
        renderer: &Renderer,
        limits: &layout::Limits,
    ) -> layout::Node {
        self.0.as_widget_mut().layout(tree, renderer, limits)
    }

    fn draw(
        &self,
        tree: &widget::Tree,
        renderer: &mut Renderer,
        theme: &Theme,
        style: &renderer::Style,
        layout: Layout<'_>,
        cursor: mouse::Cursor,
        viewport: &Rectangle,
    ) {
        self.0
            .as_widget()
            .draw(tree, renderer, theme, style, layout, cursor, viewport);
    }

    fn operate(
        &mut self,
        tree: &mut widget::Tree,
        layout: Layout<'_>,
        renderer: &Renderer,
        operation: &mut dyn widget::Operation,
    ) {
        self.0
            .as_widget_mut()
            .operate(tree, layout, renderer, operation);
    }

    fn update(
        &mut self,
        tree: &mut widget::Tree,
        event: &Event,
        layout: Layout<'_>,
        cursor: mouse::Cursor,
        renderer: &Renderer,
        _clipboard: &mut dyn Clipboard,
        shell: &mut Shell<'_, Message>,
        viewport: &Rectangle,
    ) {
        self.0.as_widget_mut().update(
            tree,
            event,
            layout,
            cursor,
            renderer,
            &mut clipboard::Null,
            shell,
            viewport,
        );
    }

    fn mouse_interaction(
        &self,
        tree: &widget::Tree,
        layout: Layout<'_>,
        cursor: mouse::Cursor,
        viewport: &Rectangle,
        renderer: &Renderer,
    ) -> mouse::Interaction {
        self.0
            .as_widget()
            .mouse_interaction(tree, layout, cursor, viewport, renderer)
    }
}
