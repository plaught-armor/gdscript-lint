# gdlint: disable-file
class_name Enemy
extends Node
## A row, not a kingdom (D4). Carries a stable id; "alive" is membership in its
## owner's set (D2b), never a bool on the node.
##
## Node (not RefCounted) only so the room can add_child + own it in the tree — the
## parent-owner shape D2b is about. A one-int record would otherwise be a
## RefCounted (D1/D5, and ~cheaper than a Node); a real enemy earns its Node by
## carrying hot runtime state this demo elides.

var id: int = 0
