extends RefCounted
## L2: one short, setting-gated buzz for confirmations a thumb cannot see
## (the finger covers the button). Browsers without the Vibration API (iOS
## Safari) simply ignore it.

const TAP_MSEC: int = 12
const REFUSE_MSEC: int = 30


static func tap(duration_msec: int = TAP_MSEC) -> void:
	if not bool(GameManager.get("haptics_enabled")):
		return
	if not (OS.has_feature("web") or OS.has_feature("mobile")):
		return
	if DisplayServer.get_name() == "headless":
		return
	Input.vibrate_handheld(duration_msec)


static func refuse() -> void:
	tap(REFUSE_MSEC)
