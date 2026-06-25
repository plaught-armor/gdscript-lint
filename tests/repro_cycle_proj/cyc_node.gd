# gdlint: disable-file
# Scene-root script that references the data Resource — the forward edge. Combined
# with CycRes.scene pointing back here, the two files form a load cycle.
extends Node

@export var def: Resource
