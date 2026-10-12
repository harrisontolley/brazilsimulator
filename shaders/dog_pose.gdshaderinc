// Shared vertex animation for the dogs (see scenes/crowd/dog_manager.gd). One mesh serves every
// breed: the shader stretches it into shape, then poses the legs, head, jaw, ears and tail.
//
// Per vertex:   UV2.x = part id, UV2.y = colour slot.
// Per instance: custom.x = animation | breed << 4 | previous animation << 8 | speed (0.2 m/s) << 12,
//               .y = time the animation last changed, .z = time of last one-shot (+ bite, - hurt),
//               .w = two 12-bit marking colours. COLOR.rgb = coat, COLOR.a = seed.

uniform float now = 0.0;

const int A_STAND = 0;
const int A_TROT = 1;
const int A_RUN = 2;
const int A_SIT = 3;
const int A_LIE = 4;
const int A_SNIFF = 5;
const int A_BARK = 6;
const int A_GROWL = 7;
const int A_DIG = 8;
const int A_SCRATCH = 9;
const int A_PEE = 10;
const int A_BEG = 11;
const int A_COWER = 12;
const int A_DEAD = 13;
const int A_WAG = 14;

const int D_BODY = 0;
const int D_HEAD = 1;
const int D_JAW = 2;
const int D_EAR_L = 3;
const int D_EAR_R = 4;
const int D_LEG_FL = 5;
const int D_LEG_FR = 6;
const int D_LEG_BL = 7;
const int D_LEG_BR = 8;
const int D_TAIL = 9;

// Where the joints are on the unstretched dog, which faces -Z.
const float HIP_Y = 0.3;
const float HIP_Z = 0.27;
const float HIP_X = 0.09;
const vec3 NECK = vec3(0.0, 0.52, -0.36);
const vec3 JAW = vec3(0.0, 0.535, -0.58);
const vec3 TAIL = vec3(0.0, 0.5, 0.34);

struct Dog {
	vec4 legs;    // forward swing at the hip: front left, front right, back left, back right
	float lift;   // back right leg cocked out sideways
	float pitch;  // nose up, hinged at the back hips
	float bow;    // chest down, hinged at the back hips the other way round
	float drop;   // whole body lower
	float roll;   // over on its side
	vec2 head;    // x: nod down, y: turn
	float jaw;    // open
	vec2 tail;    // x: raise, y: wag to one side
	float ears;   // back flat against the head
};

Dog dog_mix(Dog a, Dog b, float k) {
	return Dog(mix(a.legs, b.legs, k), mix(a.lift, b.lift, k), mix(a.pitch, b.pitch, k), mix(a.bow, b.bow, k),
			mix(a.drop, b.drop, k), mix(a.roll, b.roll, k), mix(a.head, b.head, k), mix(a.jaw, b.jaw, k),
			mix(a.tail, b.tail, k), mix(a.ears, b.ears, k));
}

// Body length, girth, leg length, head size.
vec4 breed_a(int b) {
	if (b == 1) { return vec4(0.95, 1.3, 0.85, 1.25); }   // pitbull
	if (b == 2) { return vec4(1.05, 1.4, 0.95, 1.25); }   // rottweiler
	if (b == 3) { return vec4(1.1, 1.08, 1.1, 1.05); }    // pastor alemão
	if (b == 4) { return vec4(1.05, 1.2, 1.0, 1.1); }     // labrador
	if (b == 5) { return vec4(1.4, 0.85, 0.42, 0.9); }    // salsicha
	if (b == 6) { return vec4(0.8, 0.7, 0.95, 0.8); }     // pinscher
	if (b == 7) { return vec4(0.85, 1.25, 0.9, 1.1); }    // poodle
	return vec4(1.0);                                     // vira-lata caramelo
}

// Snout length, how far the ears flop, tail length, tail carried up.
vec4 breed_b(int b) {
	if (b == 1) { return vec4(0.75, 0.55, 0.75, 0.15); }
	if (b == 2) { return vec4(0.85, 1.0, 0.3, 0.0); }
	if (b == 3) { return vec4(1.35, 0.0, 1.25, -0.45); }
	if (b == 4) { return vec4(1.1, 1.0, 1.1, 0.1); }
	if (b == 5) { return vec4(1.35, 1.0, 0.9, 0.1); }
	if (b == 6) { return vec4(0.9, 0.0, 0.35, 0.5); }
	if (b == 7) { return vec4(0.85, 1.0, 0.55, 1.1); }
	return vec4(1.0, 0.55, 1.0, 0.75);
}

Dog dog_pose(int id, float speed, float t, float ph, float seed, float leg) {
	float breath = sin(t * 2.4 + ph);
	Dog q = Dog(vec4(0.0), 0.0, 0.0, 0.0, breath * 0.004, 0.0, vec2(0.0, sin(t * 0.6 + ph) * 0.35), 0.12 + breath * 0.06,
			vec2(0.0, sin(t * 2.2 + ph) * 0.25), 0.0);
	// Short legs take more steps to cover the same ground.
	float c = t * (4.0 + speed * 2.6) / max(leg, 0.45) + ph;
	if (id == A_TROT) {
		// Opposite corners together.
		float s = sin(c);
		float amp = 0.32 + min(speed, 3.0) * 0.1;
		q.legs = vec4(s, -s, -s, s) * amp;
		q.drop = -abs(cos(c)) * 0.012;
		q.head = vec2(0.05 + sin(c * 2.0) * 0.03, sin(t * 0.7 + ph) * 0.2);
		q.tail = vec2(0.25, sin(t * 6.0 + ph) * 0.3);
	} else if (id == A_RUN) {
		// Front pair, then back pair, the back arching between them.
		float g = c * 0.8;
		float f = sin(g);
		float b = sin(g - 1.9);
		q.legs = vec4(f * 0.95 + 0.1, f * 0.85 + 0.1, b * 0.9 - 0.1, b * 1.0 - 0.1);
		q.pitch = sin(g + 0.8) * 0.13;
		q.drop = -abs(cos(g)) * 0.05;
		q.head = vec2(-0.12, 0.0);
		q.jaw = 0.35;
		q.tail = vec2(0.5 + sin(g) * 0.2, 0.0);
		q.ears = 0.8;
	} else if (id == A_SIT || id == A_BEG || id == A_SCRATCH) {
		q.pitch = 0.5;
		q.drop += 0.2;
		q.legs = vec4(-0.5, -0.5, 1.35, 1.35);
		q.head = vec2(0.3, sin(t * 0.5 + ph) * 0.5);
		q.tail = vec2(-0.6, sin(t * 3.0 + ph) * 0.5);
		if (id == A_BEG) {
			// Up on the haunches, paws paddling.
			q.pitch = 1.05;
			q.legs.xy = vec2(0.5 + sin(t * 7.0 + ph) * 0.25, 0.5 - sin(t * 7.0 + ph) * 0.25);
			q.head = vec2(0.75, 0.0);
			q.jaw = 0.4;
			q.tail = vec2(-0.6, sin(t * 11.0 + ph) * 0.8);
		} else if (id == A_SCRATCH) {
			// A back leg going at an ear.
			q.legs.w = 2.3 + sin(t * 22.0) * 0.22;
			q.head = vec2(0.5, -0.7);
			q.ears = 0.4;
			q.roll = 0.12;
		}
	} else if (id == A_LIE) {
		// Down like a sphinx, chin nearly on the paws.
		q.drop += 0.3 - 0.07;
		q.legs = vec4(1.45, 1.45, 1.45, 1.45);
		q.head = vec2(0.35 + sin(t * 0.3 + ph) * 0.1, sin(t * 0.25 + ph) * 0.3);
		q.jaw = 0.25 + breath * 0.1;
		q.tail = vec2(-0.5, sin(t * 0.8 + ph) * 0.15);
	} else if (id == A_SNIFF) {
		float s = sin(c * 0.6) * 0.18;
		q.legs = vec4(s, -s, -s, s);
		q.bow = 0.12;
		q.head = vec2(1.0 + sin(t * 9.0 + ph) * 0.06, sin(t * 1.7 + ph) * 0.4);
		q.jaw = 0.0;
		q.tail = vec2(0.5, sin(t * 7.0 + ph) * 0.5);
	} else if (id == A_BARK) {
		// Each bark throws the head up and bounces the front feet off the ground.
		float f = fract(t * 2.6 + seed * 3.0);
		float b = smoothstep(0.0, 0.08, f) * (1.0 - smoothstep(0.14, 0.3, f));
		q.pitch = b * 0.14;
		q.legs.xy = vec2(0.15 * b);
		q.head = vec2(-0.35 * b, 0.0);
		q.jaw = b * 0.9;
		q.tail = vec2(0.7, 0.0);
		q.ears = 0.3;
	} else if (id == A_GROWL) {
		// Low at the front, hackles up, everything stiff.
		q.bow = 0.2;
		q.legs = vec4(0.3, 0.3, -0.12, -0.12);
		q.head = vec2(0.25, 0.0);
		q.jaw = 0.3 + sin(t * 31.0) * 0.05;
		q.tail = vec2(0.2, 0.0);
		q.ears = 1.0;
		q.drop += 0.01 + sin(t * 37.0) * 0.003;
	} else if (id == A_DIG) {
		float s = sin(t * 15.0 + ph);
		q.bow = 0.32;
		q.legs = vec4(0.5 + s * 0.45, 0.5 - s * 0.45, -0.2, -0.2);
		q.head = vec2(0.8, 0.0);
		q.tail = vec2(0.8, sin(t * 9.0) * 0.4);
	} else if (id == A_PEE) {
		q.lift = 1.0;
		q.head = vec2(0.0, sin(t * 0.9 + ph) * 0.6);
		q.tail = vec2(0.5, 0.0);
		q.roll = -0.06;
	} else if (id == A_COWER) {
		// Belly to the ground, tail under, shaking.
		q.drop += 0.17;
		q.legs = vec4(0.75, 0.75, 0.7, 0.7);
		q.bow = 0.08;
		q.head = vec2(0.5, sin(t * 29.0) * 0.04);
		q.jaw = 0.0;
		q.tail = vec2(-1.5, 0.0);
		q.ears = 1.0;
	} else if (id == A_DEAD) {
		q.roll = 1.5;
		q.legs = vec4(0.25, -0.1, -0.25, 0.1);
		q.head = vec2(-0.2, 0.0);
		q.jaw = 0.5;
		q.tail = vec2(-0.4, 0.0);
		q.drop = 0.0;
	} else if (id == A_WAG) {
		// So pleased to see you that the back half is doing the wagging.
		float w = sin(t * 13.0 + ph);
		q.legs = vec4(0.0, 0.0, w * 0.1, -w * 0.1);
		q.pitch = abs(sin(t * 6.5 + ph)) * 0.08;
		q.legs.xy += vec2(abs(sin(t * 6.5 + ph)) * 0.2);
		q.head = vec2(-0.25, w * 0.12);
		q.jaw = 0.55;
		q.tail = vec2(0.6, w * 1.0);
		q.roll = w * 0.05;
	}
	return q;
}

void drx(inout vec3 p, inout vec3 n, vec3 o, float a) {
	float c = cos(a);
	float s = sin(a);
	p -= o;
	p = vec3(p.x, p.y * c - p.z * s, p.y * s + p.z * c) + o;
	n = vec3(n.x, n.y * c - n.z * s, n.y * s + n.z * c);
}

void dry(inout vec3 p, inout vec3 n, vec3 o, float a) {
	float c = cos(a);
	float s = sin(a);
	p -= o;
	p = vec3(p.x * c + p.z * s, p.y, -p.x * s + p.z * c) + o;
	n = vec3(n.x * c + n.z * s, n.y, -n.x * s + n.z * c);
}

void drz(inout vec3 p, inout vec3 n, vec3 o, float a) {
	float c = cos(a);
	float s = sin(a);
	p -= o;
	p = vec3(p.x * c - p.y * s, p.x * s + p.y * c, p.z) + o;
	n = vec3(n.x * c - n.y * s, n.x * s + n.y * c, n.z);
}

// Shapes and poses one vertex. dead_k: 0..1 how far a dead dog has gone over. hit_k: hit flash.
void dog_vertex(inout vec3 p, inout vec3 n, float partf, vec4 cd, float seed, out float dead_k, out float hit_k) {
	int word = int(cd.x + 0.5);
	int anim = word & 15;
	int breed = (word >> 4) & 15;
	int prev = (word >> 8) & 15;
	float speed = float((word >> 12) & 63) * 0.2;
	int part = int(partf + 0.5);
	vec4 sa = breed_a(breed);
	vec4 sb = breed_b(breed);
	float t = now;
	float ph = seed * 19.0;

	// --- the breed ---
	float raise = HIP_Y * (sa.z - 1.0);
	bool leg = part >= D_LEG_FL && part <= D_LEG_BR;
	bool front = part == D_LEG_FL || part == D_LEG_FR;
	float hip_z = HIP_Z * sa.x;
	float hip_y = HIP_Y * sa.z;
	if (leg) {
		float sx = p.x < 0.0 ? -1.0 : 1.0;
		float sz = front ? -1.0 : 1.0;
		p.y *= sa.z;
		p.z += sz * HIP_Z * (sa.x - 1.0);
		p.x += sx * HIP_X * (sa.y - 1.0);
		p.x = sx * HIP_X * sa.y + (p.x - sx * HIP_X * sa.y) * mix(1.0, sa.y, 0.6);
	} else {
		p.y += raise;
		float mid = 0.42 + raise;
		if (part == D_BODY) {
			p.z *= sa.x;
			p.x *= sa.y;
			p.y = mid + (p.y - mid) * sa.y;
		} else if (part == D_TAIL) {
			vec3 base = TAIL + vec3(0.0, raise, 0.0);
			p.z += TAIL.z * (sa.x - 1.0);
			base.z = TAIL.z * sa.x;
			p.z = base.z + (p.z - base.z) * sb.z;
			drx(p, n, base, sb.w * 1.1);
		} else {
			vec3 neck = NECK + vec3(0.0, raise, 0.0);
			// A longer nose first, then the whole head to size, then onto the end of the body.
			if (p.z < -0.6) {
				p.z = -0.6 + (p.z + 0.6) * sb.x;
			}
			if (part == D_EAR_L || part == D_EAR_R) {
				float side = part == D_EAR_L ? -1.0 : 1.0;
				drz(p, n, vec3(side * 0.085, 0.69 + raise, -0.45), -side * sb.y * 1.9);
			}
			p = neck + (p - neck) * sa.w;
			p.z += NECK.z * (sa.x - 1.0);
			p.y += 0.26 * (sa.y - 1.0) * 0.35;
		}
	}

	// --- the pose ---
	float k = smoothstep(0.0, anim == A_DEAD ? 0.5 : 0.25, t - cd.y);
	Dog q = dog_pose(anim, speed, t, ph, seed, sa.z);
	if (prev != anim && k < 1.0) {
		q = dog_mix(dog_pose(prev, speed, t, ph, seed, sa.z), q, k);
	}
	float ev = cd.z;
	float atk = ev > 0.0 ? t - ev : 99.0;
	float hurt = ev < 0.0 ? t + ev : 99.0;
	// A bite: the head snaps forward and the jaws shut on it.
	float snap = smoothstep(0.0, 0.06, atk) * (1.0 - smoothstep(0.1, 0.28, atk));
	q.head.x -= 0.3 * snap;
	q.jaw = mix(q.jaw, atk < 0.1 ? 1.0 : 0.0, snap);
	q.bow += 0.1 * snap;
	float flinch = 1.0 - smoothstep(0.0, 0.3, hurt);
	hit_k = 1.0 - smoothstep(0.0, 0.14, hurt);
	q.ears = max(q.ears, flinch);
	q.tail.x -= 1.2 * flinch;
	dead_k = anim == A_DEAD ? k : 0.0;
	if (anim == A_DEAD) {
		hit_k = 0.0;
	}

	vec3 neck = vec3(0.0, NECK.y + raise, NECK.z * sa.x);
	if (part == D_JAW) {
		vec3 hinge = neck + (JAW + vec3(0.0, raise, 0.0) - (NECK + vec3(0.0, raise, 0.0))) * sa.w;
		drx(p, n, hinge, -q.jaw * 0.6);
		part = D_HEAD;
	}
	if (part == D_EAR_L || part == D_EAR_R) {
		float side = part == D_EAR_L ? -1.0 : 1.0;
		vec3 root = neck + (vec3(side * 0.085, 0.69 + raise, -0.45) - (NECK + vec3(0.0, raise, 0.0))) * sa.w;
		drx(p, n, root, -q.ears * 0.9 * (1.0 - sb.y));
		part = D_HEAD;
	}
	if (part == D_HEAD) {
		dry(p, n, neck, q.head.y);
		drx(p, n, neck, -q.head.x);
	}
	if (part == D_TAIL) {
		vec3 base = vec3(0.0, TAIL.y + raise, TAIL.z * sa.x);
		dry(p, n, base, q.tail.y);
		drx(p, n, base, q.tail.x);
	}
	if (leg) {
		float sx = p.x < 0.0 ? -1.0 : 1.0;
		vec3 hip = vec3(sx * HIP_X * sa.y, hip_y, front ? -hip_z : hip_z);
		float a = part == D_LEG_FL ? q.legs.x : (part == D_LEG_FR ? q.legs.y : (part == D_LEG_BL ? q.legs.z : q.legs.w));
		drx(p, n, hip, a);
		if (part == D_LEG_BR) {
			drz(p, n, hip, q.lift * 1.1);
		}
	}
	// The body tips about the back hips: nose up to sit, chest down to bow. The feet that
	// stay on the ground stay where they are.
	vec3 back = vec3(0.0, hip_y, hip_z);
	vec3 fore = vec3(0.0, hip_y, -hip_z);
	bool back_leg = part == D_LEG_BL || part == D_LEG_BR;
	if (!back_leg) {
		drx(p, n, back, q.pitch);
	}
	if (!front) {
		drx(p, n, fore, -q.bow * (back_leg ? 0.0 : 1.0));
	} else {
		p.y -= 0.0;
	}
	if (front && q.bow > 0.0) {
		// Elbows fold under a lowered chest.
		p.y *= 1.0 - q.bow * 0.9;
	}
	if (!leg && q.bow > 0.0) {
		p.y -= q.bow * 0.9 * hip_y * smoothstep(hip_z, -hip_z, p.z);
	}
	p.y -= q.drop * (leg ? min(1.0, sa.z) : sa.z);
	p.y = max(p.y, leg ? 0.0 : 0.04);
	// Squash on a hit, anchored at the feet.
	p.y *= 1.0 - flinch * 0.12;
	drz(p, n, vec3(0.0), q.roll);
	p.y += abs(sin(q.roll)) * 0.13 * sa.y;
}
