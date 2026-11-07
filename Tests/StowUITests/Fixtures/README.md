# Gallery UI-test images

These JPEG images are cropped from the selected 3A-2 design proposal. They provide the same café, workspace, and mountain photographs for the final simulator screenshot comparison.

- Bundle these images only in `StowUITests`, not in the production app.
- The `--ui-testing-seed-gallery` fixture passes the image data to an isolated, in-memory Debug simulator library. Its capture spool, search index, metrics, and temporary files use a separate temporary root.
- Fixture loading does not make network requests or enable automatic link previews.

## Accessibility audit viewport

On iOS 26, the contrast audit can sample a prefetched card title below the visible gallery. Its issue screenshot then contains the search material or black pixels outside the app, not the title. Ignore a contrast report only when the element has a `card-title-UUID` identifier, its corresponding item button exists, and its frame has no intersection with the region between the navigation bar and search field. This region includes the gallery viewport and its bottom clearance. Keep reports for partially visible titles, all other elements, and all other audit types. Log both frames for each excluded report.
