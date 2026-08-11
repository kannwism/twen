APP := build/twen.app

.PHONY: app run test clean

app:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp Support/Info.plist $(APP)/Contents/Info.plist
	cp .build/release/twen $(APP)/Contents/MacOS/twen
	codesign --force --sign - $(APP)

run: app
	open $(APP)

test:
	swift test

clean:
	rm -rf .build build
