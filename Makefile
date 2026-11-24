ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = StandChillow

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = shesp
shesp_FILES = Tweak.xm
shesp_FRAMEWORKS = UIKit Foundation QuartzCore
shesp_LDFLAGS = -Wl,-undefined,dynamic_lookup

include $(THEOS)/makefiles/tweak.mk
