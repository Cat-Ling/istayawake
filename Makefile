THEOS_PACKAGE_SCHEME = rootless
TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = istayawake

istayawake_FILES = Tweak.x
istayawake_CFLAGS = -fobjc-arc
istayawake_FRAMEWORKS = UIKit Foundation

include $(THEOS)/makefiles/tweak.mk
