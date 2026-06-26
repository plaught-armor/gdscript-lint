# gdlint: disable-file
extends SceneTree
## RefCounted .new() allocation cost vs declared member-var count and method count.
## Hypothesis: methods live on the script (shared across instances), so func count
## should NOT move per-instance .new() cost; member vars DO (each instance allocates
## slots + runs default-value init). Best-of-REPS; each iter overwrites _hold so the
## prior instance drops to refcount 0 and frees — steady memory, alloc+free per iter.
## _sink reads an id so nothing is dead-code-eliminated.
##
## Run: godot --headless --script tests/bench_refcounted_alloc.gd

const N: int = 1_000_000
const REPS: int = 7

var _hold: RefCounted = null
var _sink: int = 0


class Empty extends RefCounted:
	pass

class Vars5 extends RefCounted:
	var v0: int = 0
	var v1: float = 0.0
	var v2: String = ""
	var v3: bool = false
	var v4: Vector2 = Vector2.ZERO

class Vars20 extends RefCounted:
	var v0: int = 0
	var v1: float = 0.0
	var v2: String = ""
	var v3: bool = false
	var v4: Vector2 = Vector2.ZERO
	var v5: Vector3 = Vector3.ZERO
	var v6: int = 0
	var v7: float = 0.0
	var v8: String = ""
	var v9: bool = false
	var v10: Vector2 = Vector2.ZERO
	var v11: Vector3 = Vector3.ZERO
	var v12: int = 0
	var v13: float = 0.0
	var v14: String = ""
	var v15: bool = false
	var v16: Vector2 = Vector2.ZERO
	var v17: Vector3 = Vector3.ZERO
	var v18: int = 0
	var v19: float = 0.0

class Vars50 extends RefCounted:
	var v0: int = 0
	var v1: float = 0.0
	var v2: String = ""
	var v3: bool = false
	var v4: Vector2 = Vector2.ZERO
	var v5: Vector3 = Vector3.ZERO
	var v6: int = 0
	var v7: float = 0.0
	var v8: String = ""
	var v9: bool = false
	var v10: Vector2 = Vector2.ZERO
	var v11: Vector3 = Vector3.ZERO
	var v12: int = 0
	var v13: float = 0.0
	var v14: String = ""
	var v15: bool = false
	var v16: Vector2 = Vector2.ZERO
	var v17: Vector3 = Vector3.ZERO
	var v18: int = 0
	var v19: float = 0.0
	var v20: String = ""
	var v21: bool = false
	var v22: Vector2 = Vector2.ZERO
	var v23: Vector3 = Vector3.ZERO
	var v24: int = 0
	var v25: float = 0.0
	var v26: String = ""
	var v27: bool = false
	var v28: Vector2 = Vector2.ZERO
	var v29: Vector3 = Vector3.ZERO
	var v30: int = 0
	var v31: float = 0.0
	var v32: String = ""
	var v33: bool = false
	var v34: Vector2 = Vector2.ZERO
	var v35: Vector3 = Vector3.ZERO
	var v36: int = 0
	var v37: float = 0.0
	var v38: String = ""
	var v39: bool = false
	var v40: Vector2 = Vector2.ZERO
	var v41: Vector3 = Vector3.ZERO
	var v42: int = 0
	var v43: float = 0.0
	var v44: String = ""
	var v45: bool = false
	var v46: Vector2 = Vector2.ZERO
	var v47: Vector3 = Vector3.ZERO
	var v48: int = 0
	var v49: float = 0.0

class Vars100 extends RefCounted:
	var v0: int = 0
	var v1: float = 0.0
	var v2: String = ""
	var v3: bool = false
	var v4: Vector2 = Vector2.ZERO
	var v5: Vector3 = Vector3.ZERO
	var v6: int = 0
	var v7: float = 0.0
	var v8: String = ""
	var v9: bool = false
	var v10: Vector2 = Vector2.ZERO
	var v11: Vector3 = Vector3.ZERO
	var v12: int = 0
	var v13: float = 0.0
	var v14: String = ""
	var v15: bool = false
	var v16: Vector2 = Vector2.ZERO
	var v17: Vector3 = Vector3.ZERO
	var v18: int = 0
	var v19: float = 0.0
	var v20: String = ""
	var v21: bool = false
	var v22: Vector2 = Vector2.ZERO
	var v23: Vector3 = Vector3.ZERO
	var v24: int = 0
	var v25: float = 0.0
	var v26: String = ""
	var v27: bool = false
	var v28: Vector2 = Vector2.ZERO
	var v29: Vector3 = Vector3.ZERO
	var v30: int = 0
	var v31: float = 0.0
	var v32: String = ""
	var v33: bool = false
	var v34: Vector2 = Vector2.ZERO
	var v35: Vector3 = Vector3.ZERO
	var v36: int = 0
	var v37: float = 0.0
	var v38: String = ""
	var v39: bool = false
	var v40: Vector2 = Vector2.ZERO
	var v41: Vector3 = Vector3.ZERO
	var v42: int = 0
	var v43: float = 0.0
	var v44: String = ""
	var v45: bool = false
	var v46: Vector2 = Vector2.ZERO
	var v47: Vector3 = Vector3.ZERO
	var v48: int = 0
	var v49: float = 0.0
	var v50: String = ""
	var v51: bool = false
	var v52: Vector2 = Vector2.ZERO
	var v53: Vector3 = Vector3.ZERO
	var v54: int = 0
	var v55: float = 0.0
	var v56: String = ""
	var v57: bool = false
	var v58: Vector2 = Vector2.ZERO
	var v59: Vector3 = Vector3.ZERO
	var v60: int = 0
	var v61: float = 0.0
	var v62: String = ""
	var v63: bool = false
	var v64: Vector2 = Vector2.ZERO
	var v65: Vector3 = Vector3.ZERO
	var v66: int = 0
	var v67: float = 0.0
	var v68: String = ""
	var v69: bool = false
	var v70: Vector2 = Vector2.ZERO
	var v71: Vector3 = Vector3.ZERO
	var v72: int = 0
	var v73: float = 0.0
	var v74: String = ""
	var v75: bool = false
	var v76: Vector2 = Vector2.ZERO
	var v77: Vector3 = Vector3.ZERO
	var v78: int = 0
	var v79: float = 0.0
	var v80: String = ""
	var v81: bool = false
	var v82: Vector2 = Vector2.ZERO
	var v83: Vector3 = Vector3.ZERO
	var v84: int = 0
	var v85: float = 0.0
	var v86: String = ""
	var v87: bool = false
	var v88: Vector2 = Vector2.ZERO
	var v89: Vector3 = Vector3.ZERO
	var v90: int = 0
	var v91: float = 0.0
	var v92: String = ""
	var v93: bool = false
	var v94: Vector2 = Vector2.ZERO
	var v95: Vector3 = Vector3.ZERO
	var v96: int = 0
	var v97: float = 0.0
	var v98: String = ""
	var v99: bool = false

class Funcs20 extends RefCounted:
	func m0(x: int) -> int:
		return x + 0
	func m1(x: int) -> int:
		return x + 1
	func m2(x: int) -> int:
		return x + 2
	func m3(x: int) -> int:
		return x + 3
	func m4(x: int) -> int:
		return x + 4
	func m5(x: int) -> int:
		return x + 5
	func m6(x: int) -> int:
		return x + 6
	func m7(x: int) -> int:
		return x + 7
	func m8(x: int) -> int:
		return x + 8
	func m9(x: int) -> int:
		return x + 9
	func m10(x: int) -> int:
		return x + 10
	func m11(x: int) -> int:
		return x + 11
	func m12(x: int) -> int:
		return x + 12
	func m13(x: int) -> int:
		return x + 13
	func m14(x: int) -> int:
		return x + 14
	func m15(x: int) -> int:
		return x + 15
	func m16(x: int) -> int:
		return x + 16
	func m17(x: int) -> int:
		return x + 17
	func m18(x: int) -> int:
		return x + 18
	func m19(x: int) -> int:
		return x + 19

class Funcs50 extends RefCounted:
	func m0(x: int) -> int:
		return x + 0
	func m1(x: int) -> int:
		return x + 1
	func m2(x: int) -> int:
		return x + 2
	func m3(x: int) -> int:
		return x + 3
	func m4(x: int) -> int:
		return x + 4
	func m5(x: int) -> int:
		return x + 5
	func m6(x: int) -> int:
		return x + 6
	func m7(x: int) -> int:
		return x + 7
	func m8(x: int) -> int:
		return x + 8
	func m9(x: int) -> int:
		return x + 9
	func m10(x: int) -> int:
		return x + 10
	func m11(x: int) -> int:
		return x + 11
	func m12(x: int) -> int:
		return x + 12
	func m13(x: int) -> int:
		return x + 13
	func m14(x: int) -> int:
		return x + 14
	func m15(x: int) -> int:
		return x + 15
	func m16(x: int) -> int:
		return x + 16
	func m17(x: int) -> int:
		return x + 17
	func m18(x: int) -> int:
		return x + 18
	func m19(x: int) -> int:
		return x + 19
	func m20(x: int) -> int:
		return x + 20
	func m21(x: int) -> int:
		return x + 21
	func m22(x: int) -> int:
		return x + 22
	func m23(x: int) -> int:
		return x + 23
	func m24(x: int) -> int:
		return x + 24
	func m25(x: int) -> int:
		return x + 25
	func m26(x: int) -> int:
		return x + 26
	func m27(x: int) -> int:
		return x + 27
	func m28(x: int) -> int:
		return x + 28
	func m29(x: int) -> int:
		return x + 29
	func m30(x: int) -> int:
		return x + 30
	func m31(x: int) -> int:
		return x + 31
	func m32(x: int) -> int:
		return x + 32
	func m33(x: int) -> int:
		return x + 33
	func m34(x: int) -> int:
		return x + 34
	func m35(x: int) -> int:
		return x + 35
	func m36(x: int) -> int:
		return x + 36
	func m37(x: int) -> int:
		return x + 37
	func m38(x: int) -> int:
		return x + 38
	func m39(x: int) -> int:
		return x + 39
	func m40(x: int) -> int:
		return x + 40
	func m41(x: int) -> int:
		return x + 41
	func m42(x: int) -> int:
		return x + 42
	func m43(x: int) -> int:
		return x + 43
	func m44(x: int) -> int:
		return x + 44
	func m45(x: int) -> int:
		return x + 45
	func m46(x: int) -> int:
		return x + 46
	func m47(x: int) -> int:
		return x + 47
	func m48(x: int) -> int:
		return x + 48
	func m49(x: int) -> int:
		return x + 49

class Funcs100 extends RefCounted:
	func m0(x: int) -> int:
		return x + 0
	func m1(x: int) -> int:
		return x + 1
	func m2(x: int) -> int:
		return x + 2
	func m3(x: int) -> int:
		return x + 3
	func m4(x: int) -> int:
		return x + 4
	func m5(x: int) -> int:
		return x + 5
	func m6(x: int) -> int:
		return x + 6
	func m7(x: int) -> int:
		return x + 7
	func m8(x: int) -> int:
		return x + 8
	func m9(x: int) -> int:
		return x + 9
	func m10(x: int) -> int:
		return x + 10
	func m11(x: int) -> int:
		return x + 11
	func m12(x: int) -> int:
		return x + 12
	func m13(x: int) -> int:
		return x + 13
	func m14(x: int) -> int:
		return x + 14
	func m15(x: int) -> int:
		return x + 15
	func m16(x: int) -> int:
		return x + 16
	func m17(x: int) -> int:
		return x + 17
	func m18(x: int) -> int:
		return x + 18
	func m19(x: int) -> int:
		return x + 19
	func m20(x: int) -> int:
		return x + 20
	func m21(x: int) -> int:
		return x + 21
	func m22(x: int) -> int:
		return x + 22
	func m23(x: int) -> int:
		return x + 23
	func m24(x: int) -> int:
		return x + 24
	func m25(x: int) -> int:
		return x + 25
	func m26(x: int) -> int:
		return x + 26
	func m27(x: int) -> int:
		return x + 27
	func m28(x: int) -> int:
		return x + 28
	func m29(x: int) -> int:
		return x + 29
	func m30(x: int) -> int:
		return x + 30
	func m31(x: int) -> int:
		return x + 31
	func m32(x: int) -> int:
		return x + 32
	func m33(x: int) -> int:
		return x + 33
	func m34(x: int) -> int:
		return x + 34
	func m35(x: int) -> int:
		return x + 35
	func m36(x: int) -> int:
		return x + 36
	func m37(x: int) -> int:
		return x + 37
	func m38(x: int) -> int:
		return x + 38
	func m39(x: int) -> int:
		return x + 39
	func m40(x: int) -> int:
		return x + 40
	func m41(x: int) -> int:
		return x + 41
	func m42(x: int) -> int:
		return x + 42
	func m43(x: int) -> int:
		return x + 43
	func m44(x: int) -> int:
		return x + 44
	func m45(x: int) -> int:
		return x + 45
	func m46(x: int) -> int:
		return x + 46
	func m47(x: int) -> int:
		return x + 47
	func m48(x: int) -> int:
		return x + 48
	func m49(x: int) -> int:
		return x + 49
	func m50(x: int) -> int:
		return x + 50
	func m51(x: int) -> int:
		return x + 51
	func m52(x: int) -> int:
		return x + 52
	func m53(x: int) -> int:
		return x + 53
	func m54(x: int) -> int:
		return x + 54
	func m55(x: int) -> int:
		return x + 55
	func m56(x: int) -> int:
		return x + 56
	func m57(x: int) -> int:
		return x + 57
	func m58(x: int) -> int:
		return x + 58
	func m59(x: int) -> int:
		return x + 59
	func m60(x: int) -> int:
		return x + 60
	func m61(x: int) -> int:
		return x + 61
	func m62(x: int) -> int:
		return x + 62
	func m63(x: int) -> int:
		return x + 63
	func m64(x: int) -> int:
		return x + 64
	func m65(x: int) -> int:
		return x + 65
	func m66(x: int) -> int:
		return x + 66
	func m67(x: int) -> int:
		return x + 67
	func m68(x: int) -> int:
		return x + 68
	func m69(x: int) -> int:
		return x + 69
	func m70(x: int) -> int:
		return x + 70
	func m71(x: int) -> int:
		return x + 71
	func m72(x: int) -> int:
		return x + 72
	func m73(x: int) -> int:
		return x + 73
	func m74(x: int) -> int:
		return x + 74
	func m75(x: int) -> int:
		return x + 75
	func m76(x: int) -> int:
		return x + 76
	func m77(x: int) -> int:
		return x + 77
	func m78(x: int) -> int:
		return x + 78
	func m79(x: int) -> int:
		return x + 79
	func m80(x: int) -> int:
		return x + 80
	func m81(x: int) -> int:
		return x + 81
	func m82(x: int) -> int:
		return x + 82
	func m83(x: int) -> int:
		return x + 83
	func m84(x: int) -> int:
		return x + 84
	func m85(x: int) -> int:
		return x + 85
	func m86(x: int) -> int:
		return x + 86
	func m87(x: int) -> int:
		return x + 87
	func m88(x: int) -> int:
		return x + 88
	func m89(x: int) -> int:
		return x + 89
	func m90(x: int) -> int:
		return x + 90
	func m91(x: int) -> int:
		return x + 91
	func m92(x: int) -> int:
		return x + 92
	func m93(x: int) -> int:
		return x + 93
	func m94(x: int) -> int:
		return x + 94
	func m95(x: int) -> int:
		return x + 95
	func m96(x: int) -> int:
		return x + 96
	func m97(x: int) -> int:
		return x + 97
	func m98(x: int) -> int:
		return x + 98
	func m99(x: int) -> int:
		return x + 99

class Funcs200 extends RefCounted:
	func m0(x: int) -> int:
		return x + 0
	func m1(x: int) -> int:
		return x + 1
	func m2(x: int) -> int:
		return x + 2
	func m3(x: int) -> int:
		return x + 3
	func m4(x: int) -> int:
		return x + 4
	func m5(x: int) -> int:
		return x + 5
	func m6(x: int) -> int:
		return x + 6
	func m7(x: int) -> int:
		return x + 7
	func m8(x: int) -> int:
		return x + 8
	func m9(x: int) -> int:
		return x + 9
	func m10(x: int) -> int:
		return x + 10
	func m11(x: int) -> int:
		return x + 11
	func m12(x: int) -> int:
		return x + 12
	func m13(x: int) -> int:
		return x + 13
	func m14(x: int) -> int:
		return x + 14
	func m15(x: int) -> int:
		return x + 15
	func m16(x: int) -> int:
		return x + 16
	func m17(x: int) -> int:
		return x + 17
	func m18(x: int) -> int:
		return x + 18
	func m19(x: int) -> int:
		return x + 19
	func m20(x: int) -> int:
		return x + 20
	func m21(x: int) -> int:
		return x + 21
	func m22(x: int) -> int:
		return x + 22
	func m23(x: int) -> int:
		return x + 23
	func m24(x: int) -> int:
		return x + 24
	func m25(x: int) -> int:
		return x + 25
	func m26(x: int) -> int:
		return x + 26
	func m27(x: int) -> int:
		return x + 27
	func m28(x: int) -> int:
		return x + 28
	func m29(x: int) -> int:
		return x + 29
	func m30(x: int) -> int:
		return x + 30
	func m31(x: int) -> int:
		return x + 31
	func m32(x: int) -> int:
		return x + 32
	func m33(x: int) -> int:
		return x + 33
	func m34(x: int) -> int:
		return x + 34
	func m35(x: int) -> int:
		return x + 35
	func m36(x: int) -> int:
		return x + 36
	func m37(x: int) -> int:
		return x + 37
	func m38(x: int) -> int:
		return x + 38
	func m39(x: int) -> int:
		return x + 39
	func m40(x: int) -> int:
		return x + 40
	func m41(x: int) -> int:
		return x + 41
	func m42(x: int) -> int:
		return x + 42
	func m43(x: int) -> int:
		return x + 43
	func m44(x: int) -> int:
		return x + 44
	func m45(x: int) -> int:
		return x + 45
	func m46(x: int) -> int:
		return x + 46
	func m47(x: int) -> int:
		return x + 47
	func m48(x: int) -> int:
		return x + 48
	func m49(x: int) -> int:
		return x + 49
	func m50(x: int) -> int:
		return x + 50
	func m51(x: int) -> int:
		return x + 51
	func m52(x: int) -> int:
		return x + 52
	func m53(x: int) -> int:
		return x + 53
	func m54(x: int) -> int:
		return x + 54
	func m55(x: int) -> int:
		return x + 55
	func m56(x: int) -> int:
		return x + 56
	func m57(x: int) -> int:
		return x + 57
	func m58(x: int) -> int:
		return x + 58
	func m59(x: int) -> int:
		return x + 59
	func m60(x: int) -> int:
		return x + 60
	func m61(x: int) -> int:
		return x + 61
	func m62(x: int) -> int:
		return x + 62
	func m63(x: int) -> int:
		return x + 63
	func m64(x: int) -> int:
		return x + 64
	func m65(x: int) -> int:
		return x + 65
	func m66(x: int) -> int:
		return x + 66
	func m67(x: int) -> int:
		return x + 67
	func m68(x: int) -> int:
		return x + 68
	func m69(x: int) -> int:
		return x + 69
	func m70(x: int) -> int:
		return x + 70
	func m71(x: int) -> int:
		return x + 71
	func m72(x: int) -> int:
		return x + 72
	func m73(x: int) -> int:
		return x + 73
	func m74(x: int) -> int:
		return x + 74
	func m75(x: int) -> int:
		return x + 75
	func m76(x: int) -> int:
		return x + 76
	func m77(x: int) -> int:
		return x + 77
	func m78(x: int) -> int:
		return x + 78
	func m79(x: int) -> int:
		return x + 79
	func m80(x: int) -> int:
		return x + 80
	func m81(x: int) -> int:
		return x + 81
	func m82(x: int) -> int:
		return x + 82
	func m83(x: int) -> int:
		return x + 83
	func m84(x: int) -> int:
		return x + 84
	func m85(x: int) -> int:
		return x + 85
	func m86(x: int) -> int:
		return x + 86
	func m87(x: int) -> int:
		return x + 87
	func m88(x: int) -> int:
		return x + 88
	func m89(x: int) -> int:
		return x + 89
	func m90(x: int) -> int:
		return x + 90
	func m91(x: int) -> int:
		return x + 91
	func m92(x: int) -> int:
		return x + 92
	func m93(x: int) -> int:
		return x + 93
	func m94(x: int) -> int:
		return x + 94
	func m95(x: int) -> int:
		return x + 95
	func m96(x: int) -> int:
		return x + 96
	func m97(x: int) -> int:
		return x + 97
	func m98(x: int) -> int:
		return x + 98
	func m99(x: int) -> int:
		return x + 99
	func m100(x: int) -> int:
		return x + 100
	func m101(x: int) -> int:
		return x + 101
	func m102(x: int) -> int:
		return x + 102
	func m103(x: int) -> int:
		return x + 103
	func m104(x: int) -> int:
		return x + 104
	func m105(x: int) -> int:
		return x + 105
	func m106(x: int) -> int:
		return x + 106
	func m107(x: int) -> int:
		return x + 107
	func m108(x: int) -> int:
		return x + 108
	func m109(x: int) -> int:
		return x + 109
	func m110(x: int) -> int:
		return x + 110
	func m111(x: int) -> int:
		return x + 111
	func m112(x: int) -> int:
		return x + 112
	func m113(x: int) -> int:
		return x + 113
	func m114(x: int) -> int:
		return x + 114
	func m115(x: int) -> int:
		return x + 115
	func m116(x: int) -> int:
		return x + 116
	func m117(x: int) -> int:
		return x + 117
	func m118(x: int) -> int:
		return x + 118
	func m119(x: int) -> int:
		return x + 119
	func m120(x: int) -> int:
		return x + 120
	func m121(x: int) -> int:
		return x + 121
	func m122(x: int) -> int:
		return x + 122
	func m123(x: int) -> int:
		return x + 123
	func m124(x: int) -> int:
		return x + 124
	func m125(x: int) -> int:
		return x + 125
	func m126(x: int) -> int:
		return x + 126
	func m127(x: int) -> int:
		return x + 127
	func m128(x: int) -> int:
		return x + 128
	func m129(x: int) -> int:
		return x + 129
	func m130(x: int) -> int:
		return x + 130
	func m131(x: int) -> int:
		return x + 131
	func m132(x: int) -> int:
		return x + 132
	func m133(x: int) -> int:
		return x + 133
	func m134(x: int) -> int:
		return x + 134
	func m135(x: int) -> int:
		return x + 135
	func m136(x: int) -> int:
		return x + 136
	func m137(x: int) -> int:
		return x + 137
	func m138(x: int) -> int:
		return x + 138
	func m139(x: int) -> int:
		return x + 139
	func m140(x: int) -> int:
		return x + 140
	func m141(x: int) -> int:
		return x + 141
	func m142(x: int) -> int:
		return x + 142
	func m143(x: int) -> int:
		return x + 143
	func m144(x: int) -> int:
		return x + 144
	func m145(x: int) -> int:
		return x + 145
	func m146(x: int) -> int:
		return x + 146
	func m147(x: int) -> int:
		return x + 147
	func m148(x: int) -> int:
		return x + 148
	func m149(x: int) -> int:
		return x + 149
	func m150(x: int) -> int:
		return x + 150
	func m151(x: int) -> int:
		return x + 151
	func m152(x: int) -> int:
		return x + 152
	func m153(x: int) -> int:
		return x + 153
	func m154(x: int) -> int:
		return x + 154
	func m155(x: int) -> int:
		return x + 155
	func m156(x: int) -> int:
		return x + 156
	func m157(x: int) -> int:
		return x + 157
	func m158(x: int) -> int:
		return x + 158
	func m159(x: int) -> int:
		return x + 159
	func m160(x: int) -> int:
		return x + 160
	func m161(x: int) -> int:
		return x + 161
	func m162(x: int) -> int:
		return x + 162
	func m163(x: int) -> int:
		return x + 163
	func m164(x: int) -> int:
		return x + 164
	func m165(x: int) -> int:
		return x + 165
	func m166(x: int) -> int:
		return x + 166
	func m167(x: int) -> int:
		return x + 167
	func m168(x: int) -> int:
		return x + 168
	func m169(x: int) -> int:
		return x + 169
	func m170(x: int) -> int:
		return x + 170
	func m171(x: int) -> int:
		return x + 171
	func m172(x: int) -> int:
		return x + 172
	func m173(x: int) -> int:
		return x + 173
	func m174(x: int) -> int:
		return x + 174
	func m175(x: int) -> int:
		return x + 175
	func m176(x: int) -> int:
		return x + 176
	func m177(x: int) -> int:
		return x + 177
	func m178(x: int) -> int:
		return x + 178
	func m179(x: int) -> int:
		return x + 179
	func m180(x: int) -> int:
		return x + 180
	func m181(x: int) -> int:
		return x + 181
	func m182(x: int) -> int:
		return x + 182
	func m183(x: int) -> int:
		return x + 183
	func m184(x: int) -> int:
		return x + 184
	func m185(x: int) -> int:
		return x + 185
	func m186(x: int) -> int:
		return x + 186
	func m187(x: int) -> int:
		return x + 187
	func m188(x: int) -> int:
		return x + 188
	func m189(x: int) -> int:
		return x + 189
	func m190(x: int) -> int:
		return x + 190
	func m191(x: int) -> int:
		return x + 191
	func m192(x: int) -> int:
		return x + 192
	func m193(x: int) -> int:
		return x + 193
	func m194(x: int) -> int:
		return x + 194
	func m195(x: int) -> int:
		return x + 195
	func m196(x: int) -> int:
		return x + 196
	func m197(x: int) -> int:
		return x + 197
	func m198(x: int) -> int:
		return x + 198
	func m199(x: int) -> int:
		return x + 199

class Vars20Funcs20 extends RefCounted:
	var v0: int = 0
	var v1: float = 0.0
	var v2: String = ""
	var v3: bool = false
	var v4: Vector2 = Vector2.ZERO
	var v5: Vector3 = Vector3.ZERO
	var v6: int = 0
	var v7: float = 0.0
	var v8: String = ""
	var v9: bool = false
	var v10: Vector2 = Vector2.ZERO
	var v11: Vector3 = Vector3.ZERO
	var v12: int = 0
	var v13: float = 0.0
	var v14: String = ""
	var v15: bool = false
	var v16: Vector2 = Vector2.ZERO
	var v17: Vector3 = Vector3.ZERO
	var v18: int = 0
	var v19: float = 0.0
	func m0(x: int) -> int:
		return x + 0
	func m1(x: int) -> int:
		return x + 1
	func m2(x: int) -> int:
		return x + 2
	func m3(x: int) -> int:
		return x + 3
	func m4(x: int) -> int:
		return x + 4
	func m5(x: int) -> int:
		return x + 5
	func m6(x: int) -> int:
		return x + 6
	func m7(x: int) -> int:
		return x + 7
	func m8(x: int) -> int:
		return x + 8
	func m9(x: int) -> int:
		return x + 9
	func m10(x: int) -> int:
		return x + 10
	func m11(x: int) -> int:
		return x + 11
	func m12(x: int) -> int:
		return x + 12
	func m13(x: int) -> int:
		return x + 13
	func m14(x: int) -> int:
		return x + 14
	func m15(x: int) -> int:
		return x + 15
	func m16(x: int) -> int:
		return x + 16
	func m17(x: int) -> int:
		return x + 17
	func m18(x: int) -> int:
		return x + 18
	func m19(x: int) -> int:
		return x + 19

class Vars50Funcs50 extends RefCounted:
	var v0: int = 0
	var v1: float = 0.0
	var v2: String = ""
	var v3: bool = false
	var v4: Vector2 = Vector2.ZERO
	var v5: Vector3 = Vector3.ZERO
	var v6: int = 0
	var v7: float = 0.0
	var v8: String = ""
	var v9: bool = false
	var v10: Vector2 = Vector2.ZERO
	var v11: Vector3 = Vector3.ZERO
	var v12: int = 0
	var v13: float = 0.0
	var v14: String = ""
	var v15: bool = false
	var v16: Vector2 = Vector2.ZERO
	var v17: Vector3 = Vector3.ZERO
	var v18: int = 0
	var v19: float = 0.0
	var v20: String = ""
	var v21: bool = false
	var v22: Vector2 = Vector2.ZERO
	var v23: Vector3 = Vector3.ZERO
	var v24: int = 0
	var v25: float = 0.0
	var v26: String = ""
	var v27: bool = false
	var v28: Vector2 = Vector2.ZERO
	var v29: Vector3 = Vector3.ZERO
	var v30: int = 0
	var v31: float = 0.0
	var v32: String = ""
	var v33: bool = false
	var v34: Vector2 = Vector2.ZERO
	var v35: Vector3 = Vector3.ZERO
	var v36: int = 0
	var v37: float = 0.0
	var v38: String = ""
	var v39: bool = false
	var v40: Vector2 = Vector2.ZERO
	var v41: Vector3 = Vector3.ZERO
	var v42: int = 0
	var v43: float = 0.0
	var v44: String = ""
	var v45: bool = false
	var v46: Vector2 = Vector2.ZERO
	var v47: Vector3 = Vector3.ZERO
	var v48: int = 0
	var v49: float = 0.0
	func m0(x: int) -> int:
		return x + 0
	func m1(x: int) -> int:
		return x + 1
	func m2(x: int) -> int:
		return x + 2
	func m3(x: int) -> int:
		return x + 3
	func m4(x: int) -> int:
		return x + 4
	func m5(x: int) -> int:
		return x + 5
	func m6(x: int) -> int:
		return x + 6
	func m7(x: int) -> int:
		return x + 7
	func m8(x: int) -> int:
		return x + 8
	func m9(x: int) -> int:
		return x + 9
	func m10(x: int) -> int:
		return x + 10
	func m11(x: int) -> int:
		return x + 11
	func m12(x: int) -> int:
		return x + 12
	func m13(x: int) -> int:
		return x + 13
	func m14(x: int) -> int:
		return x + 14
	func m15(x: int) -> int:
		return x + 15
	func m16(x: int) -> int:
		return x + 16
	func m17(x: int) -> int:
		return x + 17
	func m18(x: int) -> int:
		return x + 18
	func m19(x: int) -> int:
		return x + 19
	func m20(x: int) -> int:
		return x + 20
	func m21(x: int) -> int:
		return x + 21
	func m22(x: int) -> int:
		return x + 22
	func m23(x: int) -> int:
		return x + 23
	func m24(x: int) -> int:
		return x + 24
	func m25(x: int) -> int:
		return x + 25
	func m26(x: int) -> int:
		return x + 26
	func m27(x: int) -> int:
		return x + 27
	func m28(x: int) -> int:
		return x + 28
	func m29(x: int) -> int:
		return x + 29
	func m30(x: int) -> int:
		return x + 30
	func m31(x: int) -> int:
		return x + 31
	func m32(x: int) -> int:
		return x + 32
	func m33(x: int) -> int:
		return x + 33
	func m34(x: int) -> int:
		return x + 34
	func m35(x: int) -> int:
		return x + 35
	func m36(x: int) -> int:
		return x + 36
	func m37(x: int) -> int:
		return x + 37
	func m38(x: int) -> int:
		return x + 38
	func m39(x: int) -> int:
		return x + 39
	func m40(x: int) -> int:
		return x + 40
	func m41(x: int) -> int:
		return x + 41
	func m42(x: int) -> int:
		return x + 42
	func m43(x: int) -> int:
		return x + 43
	func m44(x: int) -> int:
		return x + 44
	func m45(x: int) -> int:
		return x + 45
	func m46(x: int) -> int:
		return x + 46
	func m47(x: int) -> int:
		return x + 47
	func m48(x: int) -> int:
		return x + 48
	func m49(x: int) -> int:
		return x + 49

class Vars100Funcs100 extends RefCounted:
	var v0: int = 0
	var v1: float = 0.0
	var v2: String = ""
	var v3: bool = false
	var v4: Vector2 = Vector2.ZERO
	var v5: Vector3 = Vector3.ZERO
	var v6: int = 0
	var v7: float = 0.0
	var v8: String = ""
	var v9: bool = false
	var v10: Vector2 = Vector2.ZERO
	var v11: Vector3 = Vector3.ZERO
	var v12: int = 0
	var v13: float = 0.0
	var v14: String = ""
	var v15: bool = false
	var v16: Vector2 = Vector2.ZERO
	var v17: Vector3 = Vector3.ZERO
	var v18: int = 0
	var v19: float = 0.0
	var v20: String = ""
	var v21: bool = false
	var v22: Vector2 = Vector2.ZERO
	var v23: Vector3 = Vector3.ZERO
	var v24: int = 0
	var v25: float = 0.0
	var v26: String = ""
	var v27: bool = false
	var v28: Vector2 = Vector2.ZERO
	var v29: Vector3 = Vector3.ZERO
	var v30: int = 0
	var v31: float = 0.0
	var v32: String = ""
	var v33: bool = false
	var v34: Vector2 = Vector2.ZERO
	var v35: Vector3 = Vector3.ZERO
	var v36: int = 0
	var v37: float = 0.0
	var v38: String = ""
	var v39: bool = false
	var v40: Vector2 = Vector2.ZERO
	var v41: Vector3 = Vector3.ZERO
	var v42: int = 0
	var v43: float = 0.0
	var v44: String = ""
	var v45: bool = false
	var v46: Vector2 = Vector2.ZERO
	var v47: Vector3 = Vector3.ZERO
	var v48: int = 0
	var v49: float = 0.0
	var v50: String = ""
	var v51: bool = false
	var v52: Vector2 = Vector2.ZERO
	var v53: Vector3 = Vector3.ZERO
	var v54: int = 0
	var v55: float = 0.0
	var v56: String = ""
	var v57: bool = false
	var v58: Vector2 = Vector2.ZERO
	var v59: Vector3 = Vector3.ZERO
	var v60: int = 0
	var v61: float = 0.0
	var v62: String = ""
	var v63: bool = false
	var v64: Vector2 = Vector2.ZERO
	var v65: Vector3 = Vector3.ZERO
	var v66: int = 0
	var v67: float = 0.0
	var v68: String = ""
	var v69: bool = false
	var v70: Vector2 = Vector2.ZERO
	var v71: Vector3 = Vector3.ZERO
	var v72: int = 0
	var v73: float = 0.0
	var v74: String = ""
	var v75: bool = false
	var v76: Vector2 = Vector2.ZERO
	var v77: Vector3 = Vector3.ZERO
	var v78: int = 0
	var v79: float = 0.0
	var v80: String = ""
	var v81: bool = false
	var v82: Vector2 = Vector2.ZERO
	var v83: Vector3 = Vector3.ZERO
	var v84: int = 0
	var v85: float = 0.0
	var v86: String = ""
	var v87: bool = false
	var v88: Vector2 = Vector2.ZERO
	var v89: Vector3 = Vector3.ZERO
	var v90: int = 0
	var v91: float = 0.0
	var v92: String = ""
	var v93: bool = false
	var v94: Vector2 = Vector2.ZERO
	var v95: Vector3 = Vector3.ZERO
	var v96: int = 0
	var v97: float = 0.0
	var v98: String = ""
	var v99: bool = false
	func m0(x: int) -> int:
		return x + 0
	func m1(x: int) -> int:
		return x + 1
	func m2(x: int) -> int:
		return x + 2
	func m3(x: int) -> int:
		return x + 3
	func m4(x: int) -> int:
		return x + 4
	func m5(x: int) -> int:
		return x + 5
	func m6(x: int) -> int:
		return x + 6
	func m7(x: int) -> int:
		return x + 7
	func m8(x: int) -> int:
		return x + 8
	func m9(x: int) -> int:
		return x + 9
	func m10(x: int) -> int:
		return x + 10
	func m11(x: int) -> int:
		return x + 11
	func m12(x: int) -> int:
		return x + 12
	func m13(x: int) -> int:
		return x + 13
	func m14(x: int) -> int:
		return x + 14
	func m15(x: int) -> int:
		return x + 15
	func m16(x: int) -> int:
		return x + 16
	func m17(x: int) -> int:
		return x + 17
	func m18(x: int) -> int:
		return x + 18
	func m19(x: int) -> int:
		return x + 19
	func m20(x: int) -> int:
		return x + 20
	func m21(x: int) -> int:
		return x + 21
	func m22(x: int) -> int:
		return x + 22
	func m23(x: int) -> int:
		return x + 23
	func m24(x: int) -> int:
		return x + 24
	func m25(x: int) -> int:
		return x + 25
	func m26(x: int) -> int:
		return x + 26
	func m27(x: int) -> int:
		return x + 27
	func m28(x: int) -> int:
		return x + 28
	func m29(x: int) -> int:
		return x + 29
	func m30(x: int) -> int:
		return x + 30
	func m31(x: int) -> int:
		return x + 31
	func m32(x: int) -> int:
		return x + 32
	func m33(x: int) -> int:
		return x + 33
	func m34(x: int) -> int:
		return x + 34
	func m35(x: int) -> int:
		return x + 35
	func m36(x: int) -> int:
		return x + 36
	func m37(x: int) -> int:
		return x + 37
	func m38(x: int) -> int:
		return x + 38
	func m39(x: int) -> int:
		return x + 39
	func m40(x: int) -> int:
		return x + 40
	func m41(x: int) -> int:
		return x + 41
	func m42(x: int) -> int:
		return x + 42
	func m43(x: int) -> int:
		return x + 43
	func m44(x: int) -> int:
		return x + 44
	func m45(x: int) -> int:
		return x + 45
	func m46(x: int) -> int:
		return x + 46
	func m47(x: int) -> int:
		return x + 47
	func m48(x: int) -> int:
		return x + 48
	func m49(x: int) -> int:
		return x + 49
	func m50(x: int) -> int:
		return x + 50
	func m51(x: int) -> int:
		return x + 51
	func m52(x: int) -> int:
		return x + 52
	func m53(x: int) -> int:
		return x + 53
	func m54(x: int) -> int:
		return x + 54
	func m55(x: int) -> int:
		return x + 55
	func m56(x: int) -> int:
		return x + 56
	func m57(x: int) -> int:
		return x + 57
	func m58(x: int) -> int:
		return x + 58
	func m59(x: int) -> int:
		return x + 59
	func m60(x: int) -> int:
		return x + 60
	func m61(x: int) -> int:
		return x + 61
	func m62(x: int) -> int:
		return x + 62
	func m63(x: int) -> int:
		return x + 63
	func m64(x: int) -> int:
		return x + 64
	func m65(x: int) -> int:
		return x + 65
	func m66(x: int) -> int:
		return x + 66
	func m67(x: int) -> int:
		return x + 67
	func m68(x: int) -> int:
		return x + 68
	func m69(x: int) -> int:
		return x + 69
	func m70(x: int) -> int:
		return x + 70
	func m71(x: int) -> int:
		return x + 71
	func m72(x: int) -> int:
		return x + 72
	func m73(x: int) -> int:
		return x + 73
	func m74(x: int) -> int:
		return x + 74
	func m75(x: int) -> int:
		return x + 75
	func m76(x: int) -> int:
		return x + 76
	func m77(x: int) -> int:
		return x + 77
	func m78(x: int) -> int:
		return x + 78
	func m79(x: int) -> int:
		return x + 79
	func m80(x: int) -> int:
		return x + 80
	func m81(x: int) -> int:
		return x + 81
	func m82(x: int) -> int:
		return x + 82
	func m83(x: int) -> int:
		return x + 83
	func m84(x: int) -> int:
		return x + 84
	func m85(x: int) -> int:
		return x + 85
	func m86(x: int) -> int:
		return x + 86
	func m87(x: int) -> int:
		return x + 87
	func m88(x: int) -> int:
		return x + 88
	func m89(x: int) -> int:
		return x + 89
	func m90(x: int) -> int:
		return x + 90
	func m91(x: int) -> int:
		return x + 91
	func m92(x: int) -> int:
		return x + 92
	func m93(x: int) -> int:
		return x + 93
	func m94(x: int) -> int:
		return x + 94
	func m95(x: int) -> int:
		return x + 95
	func m96(x: int) -> int:
		return x + 96
	func m97(x: int) -> int:
		return x + 97
	func m98(x: int) -> int:
		return x + 98
	func m99(x: int) -> int:
		return x + 99


func _time_new(klass: GDScript) -> int:
	var best: int = 1 << 62
	for r: int in REPS:
		var t0: int = Time.get_ticks_usec()
		for i: int in N:
			_hold = klass.new()
		var dt: int = Time.get_ticks_usec() - t0
		if dt < best:
			best = dt
		_sink += _hold.get_instance_id()
	return best


func _report(label: String, usec: int) -> void:
	var ns_per: float = float(usec) * 1000.0 / float(N)
	print("%s  %8d usec/%dM  %6.1f ns/new" % [label, usec, N / 1_000_000, ns_per])


func _init() -> void:
	print("RefCounted .new() cost — N=%d, best-of-%d (Godot 4.8.dev)" % [N, REPS])
	print("------------------------------------------------------------")
	_report("empty            (  0 var,   0 fn)", _time_new(Empty))
	_report("vars5            (  5 var,   0 fn)", _time_new(Vars5))
	_report("vars20           ( 20 var,   0 fn)", _time_new(Vars20))
	_report("vars50           ( 50 var,   0 fn)", _time_new(Vars50))
	_report("vars100          (100 var,   0 fn)", _time_new(Vars100))
	_report("funcs20          (  0 var,  20 fn)", _time_new(Funcs20))
	_report("funcs50          (  0 var,  50 fn)", _time_new(Funcs50))
	_report("funcs100         (  0 var, 100 fn)", _time_new(Funcs100))
	_report("funcs200         (  0 var, 200 fn)", _time_new(Funcs200))
	_report("vars20_funcs20   ( 20 var,  20 fn)", _time_new(Vars20Funcs20))
	_report("vars50_funcs50   ( 50 var,  50 fn)", _time_new(Vars50Funcs50))
	_report("vars100_funcs100 (100 var, 100 fn)", _time_new(Vars100Funcs100))
	print("------------------------------------------------------------")
	print("sink: %d" % _sink)
	quit()
