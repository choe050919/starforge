extends Control
class_name InventoryUI

@onready var label_material: Label = %LabelMaterial
@onready var label_mass: Label = %LabelMass

var _substance_loader: SubstanceLoader

func setup(substance_loader: SubstanceLoader) -> void:
	_substance_loader = substance_loader
	_update_display(-1, 0)

func on_inventory_changed(material_sid: int, mass_mg: int) -> void:
	_update_display(material_sid, mass_mg)

func _update_display(sid: int, mass_mg: int) -> void:
	if sid < 0 or mass_mg <= 0:
		label_material.text = "Empty"
		label_mass.text = ""
		return
	
	# 재료 이름
	var mat_name := "???"
	if _substance_loader:
		mat_name = _substance_loader.get_name_by_id(sid)
	label_material.text = mat_name
	
	# 질량 표시
	var kg := float(mass_mg) / 1_000_000.0
	if kg >= 1.0:
		label_mass.text = "%.2f kg" % kg
	else:
		label_mass.text = "%.1f g" % (kg * 1000.0)
