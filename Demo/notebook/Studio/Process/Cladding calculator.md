# Cladding calculator

How many boards to order for a wall. Tomas wrote this after we ran short on the Hartley job.

```python
import math

def boards_needed(wall_width_mm, wall_height_mm, board_width_mm=145,
                  gap_mm=10, board_length_mm=4800, waste=0.12):
    """Vertical open-joint cladding: boards across the wall, lengths cut to height."""
    across = math.ceil(wall_width_mm / (board_width_mm + gap_mm))
    per_board = board_length_mm // wall_height_mm   # whole lengths out of each board
    if per_board == 0:
        raise ValueError("wall is taller than one board")
    boards = math.ceil(across / per_board)
    return math.ceil(boards * (1 + waste))

# Okafor room: two long walls, two short ones, 2.5 m high
walls = [4800, 4800, 3600, 3600]
total = sum(boards_needed(w, 2500) for w in walls)
print(total, "boards of 4.8 m")
```

For the Okafor room that comes out at **124** boards, before the door and window openings. We don't take the openings off. The offcuts from around them go on the reveals.

Waste at 12% is right for larch. Cedar is straighter, 8% is enough.

Used in [[Okafor garden room]].
