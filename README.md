# Label Review

A native macOS app for reviewing AI object-detection labels. All app controls are in English. Images and Pascal VOC XML files stay in the selected dataset folder; edits save automatically. Moving data to `checked` is manual.

## Open

Double-click **Label Review.app** in this directory. Click **Choose folder…** (⌘O) and select the folder that directly contains the images and matching XML files. The app remembers the last folder and image.

Supported image extensions: JPEG, JPG, PNG, BMP, TIFF, WebP and HEIC, subject to macOS image decoding. An image named `example.jpeg` uses `example.xml` in the same folder. Nested folders, including `bin`, are excluded.

## Review

| Control | Action |
| --- | --- |
| ⌘1–9 / ⌘0 with a box selected | Change the selected box to that label (0 = label 10) |
| ⌘1–9 / ⌘0 with no box selected → drag | Draw a new box using that label |
| 1–9 / 0 | Select a box of that label; press again to cycle to the next matching box |
| Click a label | Draw with any label, including entries above 10 |
| Click a box or object row | Select it and inspect details |
| Drag a selected box | Move it |
| Drag a corner | Resize it |
| Delete / Backspace | Remove the selected box |
| A / D | Previous / next image |
| Go to field + Return | Jump to an image by its displayed sequence number |
| R | Move the current image and its XML to `dataset/bin` |
| ⌘Z | Undo an edit or restore a binned pair during this session |
| Esc | Cancel drawing and clear selection |
| Scroll | Zoom at the pointer |
| Option + drag | Pan |
| Fit image | Reset zoom |
| ⌘S | Retry saving if a previous save failed |

Keyboard shortcuts are suspended while typing in a field or using a dialog. R and label-number shortcuts ignore held-key repeats. Selecting another image cancels an unfinished drawing.

Label numbers follow the order in **LABELS • DRAW SHORTCUTS**. A number alone selects existing boxes of that class in object-list order, wrapping to the first after the last. If a matching box is already selected by clicking, the number selects the next matching box. Switching to a different class starts at its first box. If that class has no boxes in the current image, selection clears and a message appears. Selection never edits XML. The `0` key represents label 10, and **Fit image** resets zoom.

To correct a class, select a box with a number key or by clicking, then press **Command + the target label's number**. For example, if `1 = dog` and `2 = cat`, press `1` to select a dog box, then `⌘2` to change that box to cat. The box stays selected, its coordinates and other metadata stay intact, and the change saves automatically. Press `⌘Z` to undo. Choosing its existing label does nothing.

When no box is selected, Command + a number starts drawing with that class. Press **Esc** to clear selection first, or click a label button to draw a new box directly.

The details panel shows class, X/Y, width/height, image dimensions, and source confidence when present. Coordinates are whole pixels measured from the image's upper-left corner. Change a class with the details dropdown. To edit coordinates, type the values and click **Apply coordinates**.

**Add label** appends a class. The **−** button removes a class only if no XML in the dataset uses it; relabel or remove those objects first. Label order is stored in `.label-review-labels.json` inside the selected folder.

## Filter images by label

Under **FILTER IMAGES**, check one or more labels to show only images containing at least one selected label. For example, selecting `dog` and `cat` shows images containing either class. Matching uses the exact label name. Leave all labels unchecked, or click **Show all images**, to clear the filter.

Check **No labels** on its own to show images with no object boxes: either an XML annotation with no objects, or an image with no XML file. Invalid or unreadable XML is not treated as an unlabeled image. Combine **No labels** with a class such as `dog` to show unlabeled images or images containing that class. **Show all images** clears both kinds of filter.

The image counter, Go to field, and A/D navigation follow the filtered results. Enter the displayed sequence number and press Return to jump directly to that image. All boxes in each matching image remain visible. Filtering never changes images or XML. Saved edits, undo, and moves to/from `bin` update the results immediately. If an edit removes the current image's last matching label, the image stays visible with an **Outside filter** notice until you navigate or change the filter. Delete removes only the selected box, even when it is the last box; it never moves the image or its XML. R explicitly moves the displayed image and XML to `bin`.

When applying a filter with no matches, the canvas clears and R does nothing. Selecting another folder resets the filter.

## Files and recovery

- Viewing and navigating do not write XML. Editing saves XML atomically and preserves unrelated XML fields and object metadata. Images without XML get a new XML only after an edit.
- The app does not move accepted images or change their review status.
- R moves files to `bin`; it does not permanently delete them. Filename collisions get a unique subfolder in `bin`, keeping the image/XML filenames paired.
- After restarting, recover files manually by moving the pair from `bin` back into the dataset and reopening the folder. Undo history is session-only, with up to 100 recent edits.
- Invalid XML displays an error instead of being overwritten. Use A/D to skip it, or R to move the pair to `bin`. Invalid box geometry remains visible for repair.
- Use one editor for a dataset at a time. Auto-save updates the source XML directly.

## Build and test

The included app targets Apple Silicon and macOS 13 or later. It runs without Python, Node or extra packages. Building requires Apple's Command Line Tools with Swift.

```sh
./build.sh
./test.sh
./test.sh /absolute/path/to/dataset
```

The optional dataset argument performs a read-only scan. Tests use temporary data to verify XML preservation, label catalogs, paired bin moves and collision handling, malformed files, canvas drawing/moving/resizing geometry, and label filtering with navigation, edits, undo, and empty-result safety.
