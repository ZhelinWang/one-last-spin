extends Button

#func _input(event):
	## Check if the event is a mouse button event
	#if event is InputEventMouseButton:
		## Check if the left mouse button was pressed
		#if event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
			#print("Left mouse button clicked!")
		## Check if the right mouse button was pressed
		#elif event.button_index == MOUSE_BUTTON_RIGHT and event.is_pressed():
			#print("Right mouse button clicked!")
