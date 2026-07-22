TARGET := iphone:clang:latest:15.0
ARCHS := arm64 arm64e
# 抖音主程序可执行文件名为 Aweme
INSTALL_TARGET_PROCESSES := Aweme

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CardAutoReply
CardAutoReply_FILES = Tweak.xm Editor.mm PanelIntegration.xm
CardAutoReply_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
CardAutoReply_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
