APP := build/twen.app
ICON := build/twen.icns
ICON_SRCS := Support/AppIcon.swift Sources/TwenCore/TwenGlyph.swift

.PHONY: app run test clean

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

run: app
	open $(APP)

test:
	swift test

clean:
	rm -rf .build build
