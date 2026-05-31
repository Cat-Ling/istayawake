THEOS_PACKAGE_SCHEME = rootless
TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = wifiawake

wifiawake_FILES = Tweak.xm
wifiawake_CFLAGS = -fobjc-arc -Wno-unused-variable -Wno-deprecated-declarations
wifiawake_FRAMEWORKS = Foundation UIKit
wifiawake_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
