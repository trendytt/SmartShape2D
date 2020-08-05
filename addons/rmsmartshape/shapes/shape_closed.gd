tool
extends RMSS2D_Shape_Base
class_name RMSS2D_Shape_Closed, "../closed_shape.png"

export (float) var fill_mesh_offset: float = 0.0 setget set_fill_mesh_offset


func set_fill_mesh_offset(f: float):
	fill_mesh_offset = f
	set_as_dirty()


#########
# GODOT #
#########
func _init():
	._init()
	_is_instantiable = true


############
# OVERRIDE #
############
func remove_point(key: int):
	_points.remove_point(key)
	_close_shape()
	_update_curve(_points)
	set_as_dirty()
	emit_signal("points_modified")


func set_point_array(a: RMSS2D_Point_Array):
	_points = a.duplicate(true)
	_close_shape()
	clear_cached_data()
	_update_curve(_points)
	set_as_dirty()
	property_list_changed_notify()


func _has_minimum_point_count() -> bool:
	return _points.get_point_count() >= 3


func duplicate_self():
	var _new = .duplicate()
	return _new


# Workaround (class cannot reference itself)
func __new():
	return get_script().new()


func _build_meshes(edges: Array) -> Array:
	var meshes = []

	var produced_fill_mesh = false
	for e in edges:
		if not produced_fill_mesh:
			if e.z_index > shape_material.fill_texture_z_index:
				# Produce Fill Meshes
				for m in _build_fill_mesh(get_tessellated_points(), shape_material):
					meshes.push_back(m)
				produced_fill_mesh = true

		# Produce edge Meshes
		for m in e.get_meshes():
			meshes.push_back(m)
	if not produced_fill_mesh:
		for m in _build_fill_mesh(get_tessellated_points(), shape_material):
			meshes.push_back(m)
		produced_fill_mesh = true
	return meshes


static func scale_points(points: Array, unit_size: Vector2, units: float) -> Array:
	var new_points = []
	for i in range(points.size()):
		var i_next = (i + 1) % points.size()
		var i_prev = (i - 1)
		if i_prev < 0:
			i_prev += points.size()

		var pt = points[i]
		# Wrap around
		var pt_next = points[i_next]
		var pt_prev = points[i_prev]

		var ab = pt - pt_prev
		var bc = pt_next - pt
		var delta = (ab + bc)/2.0
		var delta_normal = delta.normalized()
		var normal = Vector2(delta.y, -delta.x).normalized()

		# This causes weird rendering if the texture isn't a square
		var vtx: Vector2 = normal * unit_size
		var offset = vtx * units

		var new_point = Vector2(pt + offset)
		new_points.push_back(new_point)
	return new_points


func _build_fill_mesh(points: Array, s_mat: RMSS2D_Material_Shape) -> Array:
	var meshes = []
	if s_mat == null:
		return meshes
	if s_mat.fill_textures.empty():
		return meshes
	if points.size() < 3:
		return meshes

	var tex = null
	if s_mat.fill_textures.empty():
		return meshes
	tex = s_mat.fill_textures[0]
	var tex_normal = null
	if not s_mat.fill_texture_normals.empty():
		tex_normal = s_mat.fill_texture_normals[0]
	var tex_size = tex.get_size()

	# Points to produce the fill mesh
	var fill_points: PoolVector2Array = PoolVector2Array()
	fill_points.resize(points.size())
	points = scale_points(points, tex_size, fill_mesh_offset)
	for i in points.size():
		fill_points[i] = points[i]

	# Produce the fill mesh
	var fill_tris: PoolIntArray = Geometry.triangulate_polygon(fill_points)
	if fill_tris.empty():
		push_error("'%s': Couldn't Triangulate shape" % name)
		return []

	var st: SurfaceTool
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in range(0, fill_tris.size() - 1, 3):
		st.add_color(Color.white)
		_add_uv_to_surface_tool(st, _convert_local_space_to_uv(points[fill_tris[i]], tex_size))
		st.add_vertex(Vector3(points[fill_tris[i]].x, points[fill_tris[i]].y, 0))
		st.add_color(Color.white)
		_add_uv_to_surface_tool(st, _convert_local_space_to_uv(points[fill_tris[i + 1]], tex_size))
		st.add_vertex(Vector3(points[fill_tris[i + 1]].x, points[fill_tris[i + 1]].y, 0))
		st.add_color(Color.white)
		_add_uv_to_surface_tool(st, _convert_local_space_to_uv(points[fill_tris[i + 2]], tex_size))
		st.add_vertex(Vector3(points[fill_tris[i + 2]].x, points[fill_tris[i + 2]].y, 0))
	st.index()
	st.generate_normals()
	st.generate_tangents()
	var array_mesh = st.commit()
	var flip = false
	var transform = Transform2D()
	var mesh_data = RMSS2D_Mesh.new(tex, tex_normal, flip, transform, [array_mesh])
	meshes.push_back(mesh_data)

	return meshes


func _close_shape() -> bool:
	"""
	Will mutate the _points to ensure this is a closed_shape
	last point will be constrained to first point
	returns true if _points is modified
	"""
	if is_shape_closed():
		return false
	if not _has_minimum_point_count():
		return false
	var key_first = _points.get_point_key_at_index(0)
	# Manually add final point
	var key_last = _points.add_point(_points.get_point_position(key_first))
	_points.set_constraint(key_first, key_last, RMSS2D_Point_Array.CONSTRAINT.ALL)
	_add_point_update()
	return true


func is_shape_closed() -> bool:
	var point_count = _points.get_point_count()
	if not _has_minimum_point_count():
		return false
	var key1 = _points.get_point_key_at_index(0)
	var key2 = _points.get_point_key_at_index(point_count - 1)
	return get_point_constraint(key1, key2) == RMSS2D_Point_Array.CONSTRAINT.ALL


func add_points(verts: Array, starting_index: int = -1, key: int = -1) -> Array:
	return .add_points(verts, adjust_add_point_index(starting_index), key)


func add_point(position: Vector2, index: int = -1, key: int = -1) -> int:
	return .add_point(position, adjust_add_point_index(index), key)


func adjust_add_point_index(index: int) -> int:
	# Don't allow a point to be added after the last point of the closed shape or before the first
	if is_shape_closed():
		if index < 0 or (index > get_point_count() - 1):
			index = max(get_point_count() - 1, 0)
		if index < 1:
			index = 1
	return index


func _add_point_update():
	# Return early if _close_shape() adds another point
	# _add_point_update() will be called again by having another point added
	if _close_shape():
		return
	._add_point_update()


func bake_collision():
	if not has_node(collision_polygon_node_path) or not is_shape_closed():
		return
	var polygon = get_node(collision_polygon_node_path)
	var collision_width = 1.0
	var collision_extends = 0.0
	var verts = get_vertices()
	var t_points = get_tessellated_points()
	if t_points.size() < 2:
		return
	var collision_quads = []
	for i in range(0, t_points.size() - 1, 1):
		var width = _get_width_for_tessellated_point(verts, t_points, i)
		collision_quads.push_back(
			_build_quad_from_point(
				t_points,
				i,
				null,
				null,
				Vector2(collision_size, collision_size),
				width,
				should_flip_edges(),
				i == 0,
				i == t_points.size() - 1,
				collision_width,
				collision_offset - 1.0,
				collision_extends
			)
		)
	_weld_quad_array(collision_quads)
	var first_quad = collision_quads[0]
	var last_quad = collision_quads.back()
	_weld_quads(last_quad, first_quad, 1.0)
	var points: PoolVector2Array = PoolVector2Array()
	# PT A
	for quad in collision_quads:
		points.push_back(
			polygon.get_global_transform().xform_inv(get_global_transform().xform(quad.pt_a))
		)

	polygon.polygon = points


func _on_dirty_update():
	if _dirty:
		clear_cached_data()
		# Close shape
		_close_shape()
		if _has_minimum_point_count():
			bake_collision()
			cache_edges()
			cache_meshes()
		update()
		_dirty = false
		emit_signal("on_dirty_update")
