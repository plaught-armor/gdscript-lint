# gdlint: disable-file
extends Node
## Empirically tests Part VI ResourceLoader cache claims on 4.8.dev.
## Runs as project main scene: godot --headless --path tests/repro_cache_proj

const P: String = "res://thing.tres"


func _ready() -> void:
	_weak_ref()
	_dedup()
	_cache_modes()
	_duplicate_shallow()
	get_tree().quit()


func _load_and_drop() -> int:
	var r: Resource = load(P)
	return r.get_instance_id() # the only ref (r) drops at return


func _weak_ref() -> void:
	# §2: is the cache strong (pins forever) or does it free when the last
	# external ref drops? Load into a local, drop it, then check has_cached.
	var before: bool = ResourceLoader.has_cached(P)
	var id: int = _load_and_drop()
	var after: bool = ResourceLoader.has_cached(P)
	print("RL2    weak/strong    | has_cached before=%s, after load+drop=%s (false=frees on last-ref-drop)" % [str(before), str(after)])


func _dedup() -> void:
	# RL3/RL13: load() dedupes by path — two loads return the same instance.
	var a: Resource = load(P)
	var b: Resource = load(P)
	var same: bool = a.get_instance_id() == b.get_instance_id()
	var cached: bool = ResourceLoader.has_cached(P)
	print("RL13   dedup-by-path  | load() twice same instance=%s | has_cached=%s (RL25)" % [str(same), str(cached)])


func _cache_modes() -> void:
	# CACHE_MODE_IGNORE returns a fresh instance; default REUSE returns the cached.
	var cached: Resource = load(P)
	var reuse: Resource = ResourceLoader.load(P, "", ResourceLoader.CACHE_MODE_REUSE)
	var ignore: Resource = ResourceLoader.load(P, "", ResourceLoader.CACHE_MODE_IGNORE)
	var reuse_same: bool = reuse.get_instance_id() == cached.get_instance_id()
	var ignore_new: bool = ignore.get_instance_id() != cached.get_instance_id()
	print("RL8    cache modes    | REUSE==cached:%s (want true)  IGNORE!=cached:%s (want true, fresh copy)" % [str(reuse_same), str(ignore_new)])


func _duplicate_shallow() -> void:
	# RL22: Resource.duplicate() is a SHALLOW copy — nested Array is shared.
	var orig: Resource = load(P)
	var orig_tags: Array = orig.get("tags")
	orig_tags.clear()
	orig_tags.append_array([1, 2, 3])
	var dup: Resource = orig.duplicate()
	(dup.get("tags") as Array).append(99)
	var shared: bool = (orig.get("tags") as Array).has(99)
	print("RL22   duplicate()    | shallow copy: mutating dup.tags changed orig.tags=%s (true=shallow/shared)" % str(shared))
