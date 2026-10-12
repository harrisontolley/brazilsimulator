// Shared vertex animation for the cartoon character mesh (see scenes/characters/char_kit.gd).
// Every limb and prop is posed here from per-instance data, so a crowd costs no script time.
//
// Per vertex:   UV.x = prop id (0 = always shown, n = needs flag bit n-1), UV2.x = part id.
// Per instance: custom.x = pose, .y = ground speed, .z = flag bits,
//               .w = time of last one-shot (+ attack, - hit; fall start for DEAD / DOWN).

uniform float now = 0.0;

const float HALF_PI = 1.5707963;

const int P_WALK = 1;
const int P_RUN = 2;
const int P_SUNBATHE = 3;
const int P_COWER = 4;
const int P_FLEE = 5;
const int P_FIGHT = 6;
const int P_AIM = 7;
const int P_DEAD = 8;
const int P_DOWN = 9;
const int P_JUMP = 10;
const int P_SLIDE = 11;
const int P_DIVE = 12;

const int PART_HEAD = 1;
const int PART_ARM_L = 2;
const int PART_FORE_L = 3;
const int PART_ARM_R = 4;
const int PART_FORE_R = 5;
const int PART_THIGH_L = 6;
const int PART_SHIN_L = 7;
const int PART_THIGH_R = 8;
const int PART_SHIN_R = 9;
const int PART_BROW_L = 10;
const int PART_BROW_R = 11;

const int F_GUN = 1 << 7;

struct Pose {
	vec3 arm_l;   // x: swing forward, y: raise sideways, z: elbow bend
	vec3 arm_r;
	vec2 leg_l;   // x: hip swing forward, y: knee bend
	vec2 leg_r;
	float spread; // legs apart
	float lean;   // torso forward
	vec2 head;    // x: nod down, y: turn
	float rise;   // root height offset
	float pitch;  // whole body tipping over: + onto the back, - onto the face
	float brow;   // 1 = angry
};

Pose pose_mix(Pose a, Pose b, float k) {
	return Pose(mix(a.arm_l, b.arm_l, k), mix(a.arm_r, b.arm_r, k), mix(a.leg_l, b.leg_l, k), mix(a.leg_r, b.leg_r, k),
			mix(a.spread, b.spread, k), mix(a.lean, b.lean, k), mix(a.head, b.head, k), mix(a.rise, b.rise, k),
			mix(a.pitch, b.pitch, k), mix(a.brow, b.brow, k));
}

Pose pose_stand(float t, float ph) {
	float sway = sin(t * 1.3 + ph) * 0.06;
	return Pose(vec3(sway, 0.07, 0.12), vec3(-sway, 0.07, 0.12), vec2(0.0), vec2(0.0),
			0.0, 0.0, vec2(0.0, sin(t * 0.5 + ph * 3.0) * 0.4), sin(t * 2.0 + ph) * 0.006, 0.0, 0.0);
}

Pose pose_stride(float c, float amp, float knee, float arm, float elbow) {
	float s = sin(c);
	return Pose(vec3(-s * arm, 0.08, elbow), vec3(s * arm, 0.08, elbow),
			vec2(s * amp, 0.1 + knee * max(0.0, cos(c))), vec2(-s * amp, 0.1 + knee * max(0.0, -cos(c))),
			0.0, 0.05, vec2(0.0), -0.5 * (1.0 - cos(s * amp)), 0.0, 0.0);
}

void rx(inout vec3 p, inout vec3 n, vec3 o, float a) {
	float c = cos(a);
	float s = sin(a);
	p -= o;
	p = vec3(p.x, p.y * c - p.z * s, p.y * s + p.z * c) + o;
	n = vec3(n.x, n.y * c - n.z * s, n.y * s + n.z * c);
}

void ry(inout vec3 p, inout vec3 n, vec3 o, float a) {
	float c = cos(a);
	float s = sin(a);
	p -= o;
	p = vec3(p.x * c + p.z * s, p.y, -p.x * s + p.z * c) + o;
	n = vec3(n.x * c + n.z * s, n.y, -n.x * s + n.z * c);
}

void rz(inout vec3 p, inout vec3 n, vec3 o, float a) {
	float c = cos(a);
	float s = sin(a);
	p -= o;
	p = vec3(p.x * c - p.y * s, p.x * s + p.y * c, p.z) + o;
	n = vec3(n.x * c - n.y * s, n.x * s + n.y * c, n.z);
}

// Poses one vertex. dead_k: 0..1 how far a corpse has fallen. hit_k: 0..1 hit flash.
void char_vertex(inout vec3 p, inout vec3 n, float propf, float partf, vec4 cd, float seed, out float dead_k, out float hit_k) {
	int pose = int(cd.x + 0.5);
	float speed = cd.y;
	int flags = int(cd.z + 0.5);
	int part = int(partf + 0.5);
	int prop = int(propf + 0.5);
	if (prop > 0 && (flags & (1 << (prop - 1))) == 0) {
		// Prop not worn: fold it into a point inside the chest. A zero normal keeps the outline off it.
		p = vec3(0.0, 1.05, 0.0);
		n = vec3(0.0);
	}

	float t = now;
	float ph = seed * 19.0;
	float ev = cd.w;
	float atk = ev > 0.0 ? t - ev : 99.0;
	float hit = ev < 0.0 ? t + ev : 99.0;
	float c = t * (2.5 + speed * 2.2) + ph;
	bool gun = (flags & F_GUN) != 0;

	Pose q = pose_stand(t, ph);
	float tremble = 0.0;
	if (pose == P_WALK) {
		q = pose_stride(c, 0.45, 0.6, 0.4, 0.25);
	} else if (pose == P_RUN) {
		q = pose_stride(c, 0.8, 1.2, 0.9, 1.3);
		q.lean = 0.22;
		q.rise *= 0.4;
	} else if (pose == P_SUNBATHE) {
		bool flip = fract(seed * 7.0) < 0.5;
		q.arm_l = vec3(0.0, flip ? 1.2 : 0.45, 0.1);
		q.arm_r = vec3(0.0, flip ? 0.45 : 1.2, 0.1);
		q.leg_l = flip ? vec2(0.9, 1.7) : vec2(0.0);
		q.leg_r = flip ? vec2(0.0) : vec2(0.9, 1.7);
		q.head = vec2(0.0);
		q.pitch = HALF_PI;
	} else if (pose == P_COWER) {
		q.arm_l = vec3(0.0, 2.5, 0.4);
		q.arm_r = vec3(0.0, 2.5, 0.4);
		q.leg_l = vec2(0.7, 1.3);
		q.leg_r = vec2(0.7, 1.3);
		q.lean = 0.25;
		q.head = vec2(0.35, 0.0);
		q.rise = -0.15;
		tremble = sin(t * 38.0 + ph) * 0.012;
	} else if (pose == P_FLEE) {
		q = pose_stride(c, 0.85, 1.2, 0.0, 0.0);
		q.arm_l = vec3(0.0, 2.6 + sin(t * 14.0 + ph) * 0.35, 0.3);
		q.arm_r = vec3(0.0, 2.6 + cos(t * 13.0 + ph) * 0.35, 0.3);
		q.lean = 0.3;
		q.rise *= 0.4;
	} else if (pose == P_FIGHT || pose == P_AIM) {
		if (speed > 0.1) {
			q = pose_stride(c, 0.8, 1.2, 0.0, 0.0);
			q.rise *= 0.4;
		} else {
			q.leg_l = vec2(0.3, 0.35);
			q.leg_r = vec2(-0.25, 0.3);
			q.rise = -0.03 + abs(sin(t * 5.0 + ph)) * 0.03;
		}
		q.head = vec2(0.0);
		q.brow = 1.0;
		if (pose == P_FIGHT) {
			q.arm_l = vec3(1.0, 0.25, 1.9);
			q.arm_r = vec3(1.0, 0.25, 1.9);
			q.lean = 0.12;
		} else {
			q.arm_l = vec3(1.25, -0.35, 0.5);
			q.arm_r = vec3(1.5, 0.0, 0.05);
			gun = true;
		}
	} else if (pose == P_JUMP) {
		q.arm_l = vec3(0.3, 1.0, 0.4);
		q.arm_r = vec3(0.3, 1.0, 0.4);
		q.leg_l = vec2(0.6, 1.0);
		q.leg_r = vec2(-0.2, 0.8);
	} else if (pose == P_SLIDE) {
		// Feet first, leaning back on one arm.
		q.arm_l = vec3(-0.5, 0.5, 0.3);
		q.arm_r = vec3(0.4, 0.9, 0.5);
		q.leg_l = vec2(0.3, 0.1);
		q.leg_r = vec2(0.9, 1.2);
		q.lean = 0.4;
		q.head = vec2(0.6, 0.0);
		q.pitch = 1.0;
	} else if (pose == P_DIVE) {
		// Flat out, arms stretched ahead.
		q.arm_l = vec3(2.9, 0.15, 0.1);
		q.arm_r = vec3(2.9, 0.15, 0.1);
		q.leg_l = vec2(-0.1, 0.15);
		q.leg_r = vec2(-0.25, 0.4);
		q.head = vec2(-0.5, 0.0);
		q.rise = 0.25;
		q.pitch = -1.25;
	}
	// Anyone carrying a pistol holds it out in front.
	if (gun && pose != P_AIM && pose != P_DEAD && pose != P_DOWN) {
		q.arm_r = vec3(1.45, 0.0, 0.05);
	}

	// One-shots: punch or recoil, and flinching from a hit.
	float e = smoothstep(0.0, 0.07, atk) * (1.0 - smoothstep(0.1, 0.32, atk));
	if (gun) {
		q.arm_r.x += 0.45 * e;
		q.lean -= 0.08 * e;
	} else {
		q.arm_r = mix(q.arm_r, vec3(1.5, 0.0, 0.05), e);
		q.lean += 0.2 * e;
	}
	float flinch = 1.0 - smoothstep(0.0, 0.3, hit);
	q.lean -= 0.35 * flinch;
	q.head.x -= 0.4 * flinch;
	hit_k = 1.0 - smoothstep(0.0, 0.14, hit);

	dead_k = 0.0;
	if (pose == P_DEAD || pose == P_DOWN) {
		float fall = smoothstep(0.0, 0.45, t - abs(ev));
		fall *= fall;
		Pose sprawl = Pose(vec3(0.0, 2.4, 0.3), vec3(0.0, 1.3, 0.6), vec2(0.0, 0.2), vec2(0.0, 0.6),
				0.25, 0.0, vec2(0.0, 0.9), 0.0, pose == P_DEAD ? -HALF_PI : HALF_PI, 0.0);
		q = pose_mix(pose_stand(t, ph), sprawl, fall);
		hit_k = 0.0;
		flinch = 0.0;
		if (pose == P_DEAD) {
			dead_k = fall;
		}
	}

	if (part == PART_BROW_L || part == PART_BROW_R) {
		float side = part == PART_BROW_L ? -1.0 : 1.0;
		rz(p, n, vec3(side * 0.075, 1.67, -0.19), side * q.brow * 0.45);
		p.y -= q.brow * 0.02;
		part = PART_HEAD;
	}
	if (part == PART_HEAD) {
		vec3 neck = vec3(0.0, 1.4, 0.0);
		ry(p, n, neck, q.head.y);
		rx(p, n, neck, -q.head.x);
	}
	if (part == PART_FORE_L) {
		rx(p, n, vec3(-0.245, 1.03, 0.0), q.arm_l.z);
		part = PART_ARM_L;
	}
	if (part == PART_ARM_L) {
		vec3 sh = vec3(-0.245, 1.3, 0.0);
		rx(p, n, sh, q.arm_l.x);
		rz(p, n, sh, -q.arm_l.y);
	}
	if (part == PART_FORE_R) {
		rx(p, n, vec3(0.245, 1.03, 0.0), q.arm_r.z);
		part = PART_ARM_R;
	}
	if (part == PART_ARM_R) {
		vec3 sh = vec3(0.245, 1.3, 0.0);
		rx(p, n, sh, q.arm_r.x);
		rz(p, n, sh, q.arm_r.y);
	}
	if (part == PART_SHIN_L) {
		rx(p, n, vec3(-0.095, 0.45, 0.0), -q.leg_l.y);
		part = PART_THIGH_L;
	}
	if (part == PART_THIGH_L) {
		vec3 hip = vec3(-0.095, 0.8, 0.0);
		rx(p, n, hip, q.leg_l.x);
		rz(p, n, hip, -q.spread);
	}
	if (part == PART_SHIN_R) {
		rx(p, n, vec3(0.095, 0.45, 0.0), -q.leg_r.y);
		part = PART_THIGH_R;
	}
	if (part == PART_THIGH_R) {
		vec3 hip = vec3(0.095, 0.8, 0.0);
		rx(p, n, hip, q.leg_r.x);
		rz(p, n, hip, q.spread);
	}
	if (part <= PART_FORE_R) {
		rx(p, n, vec3(0.0, 0.82, 0.0), -q.lean);
	}

	p.y += q.rise;
	p.x += tremble;
	// Squash and stretch on a hit, anchored at the feet.
	p.y *= 1.0 - flinch * 0.1;
	p.xz *= 1.0 + flinch * 0.06;
	rx(p, n, vec3(0.0), q.pitch);
	p.y += abs(sin(q.pitch)) * 0.17;
	if (pose == P_SUNBATHE) {
		// Centre the lying body on its spot instead of hinging at the feet.
		p.z -= 0.9;
	} else if (pose == P_DIVE) {
		p.z += 0.5;
	}
}
