APP := SPZQuickLook
DERIVED := build
SPZ_SAMPLE_BASE := https://raw.githubusercontent.com/nianticlabs/spz/main/samples

.PHONY: gen build install test ql reset fixtures

gen:
	xcodegen generate

build: gen
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) -configuration Release \
		-derivedDataPath $(DERIVED) build

LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister

install: build
	-pkill -x $(APP)
	-$(LSREGISTER) -u $(DERIVED)/Build/Products/Release/$(APP).app
	rm -rf /Applications/$(APP).app
	ditto $(DERIVED)/Build/Products/Release/$(APP).app /Applications/$(APP).app
	$(LSREGISTER) -f -R -trusted /Applications/$(APP).app
	open /Applications/$(APP).app

test: gen
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) -configuration Debug \
		-derivedDataPath $(DERIVED) test

ql:
	qlmanage -p fixtures/hornedlizard.spz

reset:
	qlmanage -r && qlmanage -r cache

fixtures:
	mkdir -p fixtures
	curl -L --max-time 300 -o fixtures/hornedlizard.spz  $(SPZ_SAMPLE_BASE)/hornedlizard.spz
	curl -L --max-time 300 -o fixtures/racoonfamily.spz  $(SPZ_SAMPLE_BASE)/racoonfamily.spz
	printf 'this is not a spz' > fixtures/broken.spz
