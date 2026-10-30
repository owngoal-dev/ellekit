.PHONY: all deb-ios-rootless deb-ios-rootful deb-ios-roothide deb-tvos-roothide build-tvos

VERSION = 1.2-3

COMMON_OPTIONS = BUILD_DIR="build/" CODE_SIGNING_ALLOWED="NO" CODE_SIGNING_REQUIRED="NO" CODE_SIGN_IDENTITY="" -configuration $(CONFIGURATION)

ifneq ($(RELEASE),)
CONFIGURATION = Release
DEB_VERSION = $(VERSION)
else
CONFIGURATION = Debug
DEB_VERSION = $(VERSION)+debug
endif

ifneq ($(MAC),)
COMMON_OPTIONS += -destination 'generic/platform=macOS'
else
COMMON_OPTIONS += -destination 'generic/platform=iOS'
endif

ifneq ($(MAC),)
PRODUCTS_DIR = build/$(CONFIGURATION)
else
PRODUCTS_DIR = build/$(CONFIGURATION)-iphoneos
endif

STAGE_DIR = work-$(ARCHITECTURE)/stage
INSTALL_ROOT = $(STAGE_DIR)/$(INSTALL_PREFIX)

# TODO: maybe split each scheme into its own target?

all: deb

clean:
	xcodebuild -scheme ellekit $(COMMON_OPTIONS) clean
	xcodebuild -scheme injector $(COMMON_OPTIONS) clean
	xcodebuild -scheme safemode-ui $(COMMON_OPTIONS) clean

build-ios:
	xcodebuild -scheme ellekit $(COMMON_OPTIONS)
	xcodebuild -scheme injector $(COMMON_OPTIONS)
	xcodebuild -scheme safemode-ui $(COMMON_OPTIONS)

build-macos:
	xcodebuild -scheme ellekit $(COMMON_OPTIONS)

TVOS_BUILD_OPTIONS = -project ellekit.xcodeproj -configuration $(CONFIGURATION) -sdk appletvos SDKROOT=appletvos TVOS_DEPLOYMENT_TARGET=16.0 IPHONEOS_DEPLOYMENT_TARGET=16.0 'ARCHS=arm64 arm64e' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
TVOS_BUILD_DIR = $(CURDIR)/build/tvos
TVOS_PRODUCTS_DIR = $(TVOS_BUILD_DIR)/$(CONFIGURATION)-appletvos

build-tvos:
	xcodebuild -scheme ellekit -destination 'generic/platform=tvOS' -derivedDataPath build/tvos/DerivedData BUILD_DIR="$(TVOS_BUILD_DIR)" $(TVOS_BUILD_OPTIONS)
	xcodebuild -scheme injector -destination 'generic/platform=tvOS' -derivedDataPath build/tvos/DerivedData BUILD_DIR="$(TVOS_BUILD_DIR)" LIBRARY_SEARCH_PATHS="$(CURDIR)/roothide/tvos" $(TVOS_BUILD_OPTIONS)
	xcodebuild -target safemode-ui SYMROOT="$(TVOS_BUILD_DIR)" OBJROOT="$(TVOS_BUILD_DIR)/Intermediates" LIBRARY_SEARCH_PATHS="$(CURDIR)/roothide/tvos" $(TVOS_BUILD_OPTIONS)

deb-ios-rootful: ARCHITECTURE = iphoneos-arm
deb-ios-rootful: INSTALL_PREFIX = 

deb-ios-rootless: ARCHITECTURE = iphoneos-arm64
deb-ios-rootless: INSTALL_PREFIX = /var/jb

deb-ios-roothide: ARCHITECTURE = iphoneos-arm64e
deb-ios-roothide: INSTALL_PREFIX = 

deb-ios-rootful deb-ios-rootless deb-ios-roothide: build-ios
	@rm -rf work-$(ARCHITECTURE)
	@mkdir -p $(STAGE_DIR)

	@# Because BSD install does not support -D
	@mkdir -p $(INSTALL_ROOT)/usr/lib/ellekit
# 	@mkdir -p $(INSTALL_ROOT)/usr/libexec/ellekit

	@install -m644 $(PRODUCTS_DIR)/libellekit.dylib $(INSTALL_ROOT)/usr/lib/libellekit.dylib
	@install -m644 $(PRODUCTS_DIR)/libinjector.dylib $(INSTALL_ROOT)/usr/lib/ellekit/libinjector.dylib
	@install -m644 $(PRODUCTS_DIR)/libsafemode-ui.dylib $(INSTALL_ROOT)/usr/lib/ellekit/MobileSafety.dylib

	@find $(INSTALL_ROOT)/usr/lib -type f -exec ldid -S {} \;
	
	@ln -s $(INSTALL_PREFIX)/usr/lib/ellekit/libinjector.dylib $(INSTALL_ROOT)/usr/lib/TweakLoader.dylib
	@ln -s $(INSTALL_PREFIX)/usr/lib/ellekit/libinjector.dylib $(INSTALL_ROOT)/usr/lib/TweakInject.dylib
	@ln -s $(INSTALL_PREFIX)/usr/lib/libellekit.dylib $(INSTALL_ROOT)/usr/lib/libsubstrate.dylib
	@ln -s $(INSTALL_PREFIX)/usr/lib/libellekit.dylib $(INSTALL_ROOT)/usr/lib/libhooker.dylib
	@ln -s $(INSTALL_PREFIX)/usr/lib/libellekit.dylib $(INSTALL_ROOT)/usr/lib/libblackjack.dylib

	@mkdir -p $(INSTALL_ROOT)/usr/lib/TweakInject

	@mkdir -p $(INSTALL_ROOT)/Library/Frameworks/CydiaSubstrate.framework
	@ln -s ${INSTALL_PREFIX}/usr/lib/libellekit.dylib $(INSTALL_ROOT)/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate
	@mkdir -p $(INSTALL_ROOT)/Library/MobileSubstrate
	@ln -s ${INSTALL_PREFIX}/usr/lib/TweakInject $(INSTALL_ROOT)/Library/MobileSubstrate/DynamicLibraries

	@mkdir -p $(INSTALL_ROOT)/usr/share/doc/ellekit
	@install -m644 LICENSE $(INSTALL_ROOT)/usr/share/doc/ellekit/LICENSE

	@mkdir -p $(STAGE_DIR)/DEBIAN
	@sed -e "s|@DEB_VERSION@|$(DEB_VERSION)|g" -e "s|@DEB_ARCH@|$(ARCHITECTURE)|g" packaging/control >$(STAGE_DIR)/DEBIAN/control
	@sed -e "s|@DEB_VERSION@|$(DEB_VERSION)|g" -e "s|@DEB_ARCH@|$(ARCHITECTURE)|g" -e "s|@INSTALL_PREFIX@|$(INSTALL_PREFIX)|g" packaging/preinst >$(STAGE_DIR)/DEBIAN/preinst
	@sed -e "s|@DEB_VERSION@|$(DEB_VERSION)|g" -e "s|@DEB_ARCH@|$(ARCHITECTURE)|g" -e "s|@INSTALL_PREFIX@|$(INSTALL_PREFIX)|g" packaging/postinst >$(STAGE_DIR)/DEBIAN/postinst
	@sed -e "s|@DEB_VERSION@|$(DEB_VERSION)|g" -e "s|@DEB_ARCH@|$(ARCHITECTURE)|g" -e "s|@INSTALL_PREFIX@|$(INSTALL_PREFIX)|g" packaging/postrm >$(STAGE_DIR)/DEBIAN/postrm
	@chmod 0755 $(STAGE_DIR)/DEBIAN/preinst $(STAGE_DIR)/DEBIAN/postinst $(STAGE_DIR)/DEBIAN/postrm

	@rm -rf packages
	@mkdir -p packages
	dpkg-deb --root-owner-group -b $(STAGE_DIR) packages/ellekit_$(DEB_VERSION)_$(ARCHITECTURE).deb
	
# 	@rm -rf work-$(ARCHITECTURE)

deb-tvos-roothide: ARCHITECTURE = appletvos-arm64e
deb-tvos-roothide: INSTALL_PREFIX =
deb-tvos-roothide: build-tvos
	@rm -rf work-$(ARCHITECTURE)
	@mkdir -p $(INSTALL_ROOT)/usr/lib/ellekit $(INSTALL_ROOT)/usr/lib/TweakInject
	@install -m644 $(TVOS_PRODUCTS_DIR)/libellekit.dylib $(INSTALL_ROOT)/usr/lib/libellekit.dylib
	@install -m644 $(TVOS_PRODUCTS_DIR)/libinjector.dylib $(INSTALL_ROOT)/usr/lib/ellekit/libinjector.dylib
	@install -m644 $(TVOS_PRODUCTS_DIR)/libsafemode-ui.dylib $(INSTALL_ROOT)/usr/lib/ellekit/MobileSafety.dylib
	@find $(INSTALL_ROOT)/usr/lib -type f -exec ldid -S {} \;
	@ln -s /usr/lib/ellekit/libinjector.dylib $(INSTALL_ROOT)/usr/lib/TweakLoader.dylib
	@ln -s /usr/lib/ellekit/libinjector.dylib $(INSTALL_ROOT)/usr/lib/TweakInject.dylib
	@ln -s /usr/lib/libellekit.dylib $(INSTALL_ROOT)/usr/lib/libsubstrate.dylib
	@ln -s /usr/lib/libellekit.dylib $(INSTALL_ROOT)/usr/lib/libhooker.dylib
	@ln -s /usr/lib/libellekit.dylib $(INSTALL_ROOT)/usr/lib/libblackjack.dylib
	@mkdir -p $(INSTALL_ROOT)/Library/Frameworks/CydiaSubstrate.framework $(INSTALL_ROOT)/Library/MobileSubstrate
	@ln -s /usr/lib/libellekit.dylib $(INSTALL_ROOT)/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate
	@ln -s /usr/lib/TweakInject $(INSTALL_ROOT)/Library/MobileSubstrate/DynamicLibraries
	@mkdir -p $(INSTALL_ROOT)/usr/share/doc/ellekit $(STAGE_DIR)/DEBIAN
	@install -m644 LICENSE $(INSTALL_ROOT)/usr/share/doc/ellekit/LICENSE
	@sed -e "s|@DEB_VERSION@|$(DEB_VERSION)|g" -e "s|@DEB_ARCH@|$(ARCHITECTURE)|g" packaging/control >$(STAGE_DIR)/DEBIAN/control
	@sed -e "s|@DEB_VERSION@|$(DEB_VERSION)|g" -e "s|@DEB_ARCH@|$(ARCHITECTURE)|g" -e "s|@INSTALL_PREFIX@|$(INSTALL_PREFIX)|g" packaging/preinst >$(STAGE_DIR)/DEBIAN/preinst
	@sed -e "s|@DEB_VERSION@|$(DEB_VERSION)|g" -e "s|@DEB_ARCH@|$(ARCHITECTURE)|g" -e "s|@INSTALL_PREFIX@|$(INSTALL_PREFIX)|g" packaging/postinst >$(STAGE_DIR)/DEBIAN/postinst
	@sed -e "s|@DEB_VERSION@|$(DEB_VERSION)|g" -e "s|@DEB_ARCH@|$(ARCHITECTURE)|g" -e "s|@INSTALL_PREFIX@|$(INSTALL_PREFIX)|g" packaging/postrm >$(STAGE_DIR)/DEBIAN/postrm
	@chmod 0755 $(STAGE_DIR)/DEBIAN/preinst $(STAGE_DIR)/DEBIAN/postinst $(STAGE_DIR)/DEBIAN/postrm
	@mkdir -p packages
	dpkg-deb --root-owner-group -b $(STAGE_DIR) packages/ellekit_$(DEB_VERSION)_$(ARCHITECTURE).deb

deb-ios: deb-ios-rootful deb-ios-rootless deb-ios-roothide

deb-macos: ARCHITECTURE = macos
deb-macos: build-macos
	@rm -rf work-$(ARCHITECTURE)
	@mkdir -p $(STAGE_DIR)

	@# Because BSD install does not support -D
	@mkdir -p $(INSTALL_ROOT)/Library/TweakInject
	@mkdir -p $(INSTALL_ROOT)/Library/Frameworks
	@mkdir -p $(INSTALL_ROOT)/usr/local/bin
	@mkdir -p $(INSTALL_ROOT)/usr/local/lib

	@install -m644 $(PRODUCTS_DIR)/libellekit.dylib $(INSTALL_ROOT)/Library/TweakInject/ellekit.dylib

	@find $(INSTALL_ROOT)/Library/TweakInject -type f -exec ldid -S {} \;
	@find $(INSTALL_ROOT)/usr/local/ -type f -exec ldid -S {} \;

	@ln -s $(INSTALL_PREFIX)/Library/TweakInject/ellekit.dylib $(INSTALL_ROOT)/usr/local/lib/libsubstrate.dylib
	@ln -s $(INSTALL_PREFIX)/Library/TweakInject/ellekit.dylib $(INSTALL_ROOT)/Library/Frameworks/libsubstrate.dylib
	@ln -s $(INSTALL_PREFIX)/Library/TweakInject/ellekit.dylib $(INSTALL_ROOT)/Library/Frameworks/ellekit.dylib

	@mkdir -p $(INSTALL_ROOT)/usr/local/share/doc/ellekit
	@install -m644 LICENSE $(INSTALL_ROOT)/usr/local/share/doc/ellekit/LICENSE
	
	@rm -rf packages
	@mkdir -p packages
	@tar -czvf packages/ellekit_$(DEB_VERSION)_$(ARCHITECTURE).tar.gz -C ./$(STAGE_DIR) .
	@rm -rf work-$(ARCHITECTURE)

ifneq ($(MAC),)
deb: deb-macos
else
deb: deb-ios
endif

ifneq ($(MAC),)
build: build-macos
else
build: build-ios
endif

# Keep both visionOS fallback formats reproducible from the same source revision.
VISIONOS_BUILD_DIR = $(CURDIR)/build/visionos
VISIONOS_BUILD_OPTIONS = -project ellekit.xcodeproj -configuration $(CONFIGURATION) -sdk xros SDKROOT=xros SUPPORTED_PLATFORMS=xros XROS_DEPLOYMENT_TARGET=1.0 'ARCHS=arm64 arm64e' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO SYMROOT="$(VISIONOS_BUILD_DIR)" OBJROOT="$(VISIONOS_BUILD_DIR)/Intermediates"

.PHONY: build-visionos build-visionos-compat
build-visionos:
	xcodebuild -target ellekit $(VISIONOS_BUILD_OPTIONS) LD_DYLIB_INSTALL_NAME=@rpath/CydiaSubstrate.framework/CydiaSubstrate

build-visionos-compat:
	xcodebuild -project ellekit.xcodeproj -target ellekit -configuration $(CONFIGURATION) -sdk iphoneos SDKROOT=iphoneos IPHONEOS_DEPLOYMENT_TARGET=15.0 'ARCHS=arm64 arm64e' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO SYMROOT="$(CURDIR)/build/visionos-compat" OBJROOT="$(CURDIR)/build/visionos-compat/Intermediates" LD_DYLIB_INSTALL_NAME=@rpath/CydiaSubstrate.framework/CydiaSubstrate
