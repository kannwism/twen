APP := build/twen.app
ICON := build/twen.icns
ICON_SRCS := Support/AppIcon.swift Sources/TwenCore/TwenGlyph.swift

.PHONY: app run test clean readme-icons

app: $(ICON)
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp Support/Info.plist $(APP)/Contents/Info.plist
	cp .build/release/twen $(APP)/Contents/MacOS/twen
	cp $(ICON) $(APP)/Contents/Resources/twen.icns
	codesign --force --sign - $(APP)

# The app icon is the menu bar glyph's geometry rendered onto Apple's icon grid
# (see Support/AppIcon.swift); rebuilt only when the glyph or the renderer changes.
$(ICON): $(ICON_SRCS)
	mkdir -p build
	rm -rf build/twen.iconset
	swiftc -O $(ICON_SRCS) -o build/appicon
	build/appicon build/twen.iconset
	iconutil -c icns build/twen.iconset -o $(ICON)

# The README's menu bar state images, drawn from the same glyph (see
# Support/ReadmeIcons.swift). Committed, so rerun this when the glyph changes.
readme-icons:
	mkdir -p build
	swiftc -O Support/ReadmeIcons.swift Sources/TwenCore/TwenGlyph.swift -o build/readmeicons
	build/readmeicons docs/icons

run: app
	open $(APP)

test:
	swift test

clean:
	rm -rf .build build
