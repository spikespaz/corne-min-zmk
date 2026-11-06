/*
 * Copyright (c) 2026 Jacob Birkett
 *
 * SPDX-License-Identifier: MIT
 */

#define DT_DRV_COMPAT zmk_behavior_usb_toggle

#include <zephyr/device.h>
#include <zephyr/devicetree.h>
#include <drivers/behavior.h>

#include <zmk/ble.h>
#include <zmk/behavior.h>
#include <zmk/endpoints.h>

#include <zephyr/logging/log.h>
LOG_MODULE_DECLARE(zmk, CONFIG_ZMK_LOG_LEVEL);

#if DT_HAS_COMPAT_STATUS_OKAY(DT_DRV_COMPAT)

/* Toggle from the active output, not the stored preference as `&out OUT_TOG`
 * does. USB is always stored, since it takes over only once a host enumerates
 * the keyboard. BLE is stored only when connected: a profile reconnects on its
 * own, and would otherwise pull output away with no action from the user.
 */
static int on_keymap_binding_pressed(struct zmk_behavior_binding *binding,
                                     struct zmk_behavior_binding_event event) {
    if (zmk_endpoints_selected().transport == ZMK_TRANSPORT_BLE) {
        zmk_endpoints_select_transport(ZMK_TRANSPORT_USB);
    } else if (zmk_ble_active_profile_is_connected()) {
        zmk_endpoints_select_transport(ZMK_TRANSPORT_BLE);
    }

    return ZMK_BEHAVIOR_OPAQUE;
}

static int on_keymap_binding_released(struct zmk_behavior_binding *binding,
                                      struct zmk_behavior_binding_event event) {
    return ZMK_BEHAVIOR_OPAQUE;
}

static const struct behavior_driver_api behavior_usb_toggle_driver_api = {
    .binding_pressed = on_keymap_binding_pressed,
    .binding_released = on_keymap_binding_released,
#if IS_ENABLED(CONFIG_ZMK_BEHAVIOR_METADATA)
    .get_parameter_metadata = zmk_behavior_get_empty_param_metadata,
#endif // IS_ENABLED(CONFIG_ZMK_BEHAVIOR_METADATA)
};

BEHAVIOR_DT_INST_DEFINE(0, NULL, NULL, NULL, NULL, POST_KERNEL, CONFIG_KERNEL_INIT_PRIORITY_DEFAULT,
                        &behavior_usb_toggle_driver_api);

#endif /* DT_HAS_COMPAT_STATUS_OKAY(DT_DRV_COMPAT) */
