# gdlint: disable-file
class_name Door
extends Node
## A genuinely tree-wide interactable. Joins &"interactable" (D2b LEGIT group):
## no single system owns the door's "is interactable" fact — the player's interact
## raycast queries the whole tree for it. Owner-less + decoupled = the group's job.
