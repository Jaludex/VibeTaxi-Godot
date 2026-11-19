extends CPUParticles2D

## Self-cleaning one-shot or timed burst particle effect.


func trigger(p_color: Color, p_amount: int = 12, p_duration: float = 0.0) -> void:
	color = p_color
	amount = p_amount
	one_shot = p_duration <= 0.0
	explosiveness = 0.0 if p_duration > 0.0 else 1.0
	emitting = true
	if one_shot:
		finished.connect(queue_free)
	else:
		get_tree().create_timer(p_duration).timeout.connect(func() -> void:
			if is_instance_valid(self):
				emitting = false
				get_tree().create_timer(lifetime + 0.1).timeout.connect(func() -> void:
					if is_instance_valid(self):
						queue_free()
				)
		)
