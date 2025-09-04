class_name Utils

static func segments_intersect(p1: Vector2, p2: Vector2, q1: Vector2, q2: Vector2) -> bool:
	"""
	Retorna true se os segmentos (p1,p2) e (q1,q2) se intersectam.
	"""

	var o1 = orientation(p1, p2, q1)
	var o2 = orientation(p1, p2, q2)
	var o3 = orientation(q1, q2, p1)
	var o4 = orientation(q1, q2, p2)

	if o1 != o2 and o3 != o4:
		return true

	return false

static func orientation(a: Vector2, b: Vector2, c: Vector2) -> int:
	var val = (b.y - a.y) * (c.x - b.x) - (b.x - a.x) * (c.y - b.y)
	if abs(val) < 0.00001:
		return 0
	return 1 if val > 0 else 2
