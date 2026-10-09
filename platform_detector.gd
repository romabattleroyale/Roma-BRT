extends Node
signal platform_changed(is_mobile: bool)
var is_mobile := false
func _ready() -> void:
    is_mobile = OS.get_name() in ["Android", "iOS"]
    platform_changed.emit(is_mobile)
