LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE := greenvpn-hysteria-bridge
LOCAL_SRC_FILES := greenvpn_hysteria_bridge.c
LOCAL_CFLAGS := -Wall -Wextra -Werror -fvisibility=hidden
LOCAL_LDFLAGS := -Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384
include $(BUILD_SHARED_LIBRARY)

include $(LOCAL_PATH)/hev-socks5-tunnel/Android.mk
