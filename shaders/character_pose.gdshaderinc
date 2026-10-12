// Shared vertex animation for the cartoon character mesh (see scenes/characters/char_kit.gd).
// Every limb and prop is posed here from per-instance data, so a crowd costs no script time.
//
// Per vertex:   UV.x = prop id (see prop_shown), UV2.x = part id.
// Per instance: custom.x = pose | previous pose << 6 | speed (0.2 m/s) << 12 | held weapon << 18,
//               .y = time the pose last changed (the old one blends out from there),
//               .z = flag bits, .w = time of last one-shot (+ attack, - hit).
//
// Players are "rigged": their pose arrives whole in rig0..rig4 from scenes/characters/char_rig.gd,
// which can smooth and interrupt transitions in ways a stateless shader cannot.

uniform float now = 0.0;
// How far gone whoever is watching is: up to 1 swells every head, past 1.5 everyone is a cop.
uniform float trip = 0.0;
// 0..1 while the whole beach is celebrating: anyone idle throws their arms up.
uniform float cheer = 0.0;
uniform bool rigged = false;
uniform vec4 rig0 = vec4(0.0);  // arm_l, spread
uniform vec4 rig1 = vec4(0.0);  // arm_r, lean
uniform vec4 rig2 = vec4(0.0);  // leg_l, leg_r
uniform vec4 rig3 = vec4(0.0);  // head, rise, pitch
uniform vec4 rig4 = vec4(0.0);  // brow, shift, squash, unused

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
const int P_DANCE = 13;
const int P_CHEER = 14;
const int P_SIT = 15;
const int P_RIDE = 16;
const int P_DRUM = 17;
const int P_KO = 18;
const int P_TACKLED = 19;
const int P_HANDS_UP = 20;
const int P_CALL = 21;
const int P_DRINK = 22;
const int P_EAT = 23;
const int P_TALK = 24;
const int P_PHONE = 25;
const int P_DIG = 26;
const int P_KEEPUP = 27;
const int P_LEAN = 28;
const int P_SQUAT = 29;
const int P_SIT_DRINK = 30;
const int P_SIT_TALK = 31;
const int P_SIT_PHONE = 32;
const int P_SELFIE = 33;
const int P_CROUCH = 34;
const int P_GINGA = 35;
const int P_CLAP = 36;
const int P_LIFT = 37;
const int P_WORK = 38;
const int P_WAVE = 39;
const int P_POINT = 40;
const int P_ARGUE = 41;
const int P_SHRUG = 42;
const int P_LAUGH = 43;
const int P_STRETCH = 44;
const int P_PUSHUP = 45;
const int P_SMOKE = 46;
const int P_YAWN = 47;
const int P_LOOK = 48;
const int P_TIE = 49;
const int P_HUG = 50;
const int P_BEG = 51;
const int P_STAGGER = 52;
const int P_TEXT_WALK = 53;
const int P_LIMP = 54;
const int P_CRAWL = 55;
const int P_SCREAM = 56;
const int P_PANIC = 57;
const int P_SWEEP = 58;
const int P_PHOTO = 59;
const int P_FILM = 60;
const int P_AIM_LONG = 61;
const int P_AIM_SHOULDER = 62;
const int P_PREACH = 63;

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

// Held weapons from HELD_GUN to HELD_LAUNCHER are guns; from HELD_LONG they take two hands.
const int HELD_GUN = 2;
const int HELD_LONG = 5;
const int HELD_LAUNCHER = 8;
const int PROP_CUP = 41;
const int PROP_PHONE = 42;
const int PROP_SPADE = 43;
// Whatever is in the right hand: PROP_HELD + its held id.
const int PROP_HELD = 64;

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
	float shift;  // slide along the facing, so a lying body sits on its spot
};

Pose pose_mix(Pose a, Pose b, float k) {
	return Pose(mix(a.arm_l, b.arm_l, k), mix(a.arm_r, b.arm_r, k), mix(a.leg_l, b.leg_l, k), mix(a.leg_r, b.leg_r, k),
			mix(a.spread, b.spread, k), mix(a.lean, b.lean, k), mix(a.head, b.head, k), mix(a.rise, b.rise, k),
			mix(a.pitch, b.pitch, k), mix(a.brow, b.brow, k), mix(a.shift, b.shift, k));
}

// Standing about. Everyone has a habit (hands on hips, arms folded, weight on one leg, hands
// behind the back, a tapping foot...) and now and then does something small: scratches their
// head, looks at their watch, glances over a shoulder, rolls their neck.
Pose pose_stand(float t, float ph, float seed) {
	float sway = sin(t * 1.3 + ph) * 0.06;
	Pose q = Pose(vec3(sway, 0.07, 0.12), vec3(-sway, 0.07, 0.12), vec2(0.0), vec2(0.0),
			0.0, 0.0, vec2(0.0, sin(t * 0.5 + ph * 3.0) * 0.4), sin(t * 2.0 + ph) * 0.006, 0.0, 0.0, 0.0);
	float habit = fract(seed * 23.0);
	if (habit < 0.13) {
		q.arm_l = vec3(-0.25, 0.6, 1.5);
		q.arm_r = vec3(-0.25, 0.6, 1.5);
	} else if (habit < 0.25) {
		q.arm_l = vec3(0.6, -0.4, 1.9 + sway);
		q.arm_r = vec3(0.5, -0.4, 1.9 - sway);
	} else if (habit < 0.4) {
		float w = sin(t * 0.35 + ph);
		q.leg_l = vec2(0.12, 0.25) * max(0.0, w);
		q.leg_r = vec2(0.12, 0.25) * max(0.0, -w);
		q.lean = 0.03;
	} else if (habit < 0.5) {
		// Hands behind the back, rocking on the heels.
		q.arm_l = vec3(-0.45, -0.1, 0.7);
		q.arm_r = vec3(-0.45, -0.1, 0.7);
		q.lean = -0.04 + sin(t * 0.9 + ph) * 0.03;
		q.rise += max(0.0, sin(t * 0.9 + ph)) * 0.025;
	} else if (habit < 0.6) {
		// One hand on a hip, the weight on the other leg.
		q.arm_l = vec3(-0.25, 0.6, 1.5);
		q.leg_r = vec2(0.1, 0.22);
		q.spread = 0.05;
	} else if (habit < 0.68) {
		// Hands in pockets, a foot tapping.
		q.arm_l = vec3(0.12, -0.05, 0.4);
		q.arm_r = vec3(0.12, -0.05, 0.4);
		q.leg_l = vec2(0.2 + max(0.0, sin(t * 7.0 + ph)) * 0.12, 0.1);
	} else if (habit < 0.75) {
		// Rubbing the back of the neck.
		q.arm_l = vec3(0.3, 1.0, 2.5 + sin(t * 3.0 + ph) * 0.08);
		q.head.x = 0.15;
	}
	float f = fract(t * 0.09 + seed * 3.0);
	float kind = fract(seed * 31.0);
	float bump = smoothstep(0.0, 0.04, f) * (1.0 - smoothstep(0.1, 0.14, f));
	if (kind > 0.75) {
		// A scratch of the head.
		q.arm_r = mix(q.arm_r, vec3(0.4, 0.9, 2.3 + sin(t * 16.0) * 0.12), bump);
		q.head.x += 0.2 * bump;
	} else if (kind > 0.55) {
		// What time is it?
		q.arm_l = mix(q.arm_l, vec3(0.75, -0.35, 1.7), bump);
		q.head = mix(q.head, vec2(0.45, -0.3), bump);
	} else if (kind > 0.35) {
		// Who is that behind me?
		q.head.y = mix(q.head.y, 1.25 * sign(fract(seed * 47.0) - 0.5), bump);
		q.lean -= 0.03 * bump;
	} else if (kind > 0.2) {
		// Rolling a stiff neck.
		q.head = mix(q.head, vec2(sin(t * 4.0) * 0.3, cos(t * 4.0) * 0.5), bump);
		q.arm_l.y += 0.1 * bump;
		q.arm_r.y += 0.1 * bump;
	}
	return q;
}

Pose pose_stride(float c, float amp, float knee, float arm, float elbow) {
	float s = sin(c);
	return Pose(vec3(-s * arm, 0.08, elbow), vec3(s * arm, 0.08, elbow),
			vec2(s * amp, 0.1 + knee * max(0.0, cos(c))), vec2(-s * amp, 0.1 + knee * max(0.0, -cos(c))),
			0.0, 0.05, vec2(sin(c * 2.0) * 0.03, s * 0.06), -0.5 * (1.0 - cos(s * amp)), 0.0, 0.0, 0.0);
}

Pose pose_cheer(float t, float ph) {
	float w = sin(t * 12.0 + ph) * 0.25;
	return Pose(vec3(0.0, 2.7 + w, 0.2), vec3(0.0, 2.7 - w, 0.2), vec2(0.1, 0.25), vec2(0.1, 0.25),
			0.08, -0.05, vec2(-0.3, 0.0), abs(sin(t * 6.0 + ph)) * 0.2, 0.0, 0.0, 0.0);
}

// The pose for one id at time t. `speed` is ground speed, or how animated a talker is.
Pose pose_for(int id, float speed, float t, float ph, float seed) {
	Pose q = pose_stand(t, ph, seed);
	float c = t * (2.5 + speed * 2.2) + ph;
	// Seated versions of the standing habits share their arms.
	bool seated = id == P_SIT || id == P_SIT_DRINK || id == P_SIT_TALK || id == P_SIT_PHONE;
	if (id == P_SIT_DRINK) {
		id = P_DRINK;
	} else if (id == P_SIT_TALK) {
		id = P_TALK;
	} else if (id == P_SIT_PHONE) {
		id = P_PHONE;
	}
	// Nobody walks quite alike.
	float gait = 0.85 + fract(seed * 5.0) * 0.3;
	if (id == P_WALK) {
		q = pose_stride(c, 0.45 * gait, 0.6, 0.4 * gait, 0.25);
		// And nobody carries themselves quite alike either.
		float style = fract(seed * 61.0);
		if (style < 0.14) {
			// Hands in pockets.
			q.arm_l = vec3(0.12, -0.05, 0.4);
			q.arm_r = vec3(0.12, -0.05, 0.4);
		} else if (style < 0.26) {
			// One arm kept still, as if minding a bag.
			q.arm_r = vec3(0.3, 0.05, 1.1);
		} else if (style < 0.4) {
			// A bounce in the step and a nod in time with it.
			q.rise += abs(sin(c)) * 0.035;
			q.head.x += sin(c * 2.0) * 0.07;
		} else if (style < 0.5) {
			// Shoulders back, arms swinging wide.
			q.arm_l.y = 0.3;
			q.arm_r.y = 0.3;
			q.lean = -0.02;
		} else if (style < 0.58) {
			// Stooped, watching the ground.
			q.lean = 0.16;
			q.head.x = 0.3;
		}
		// Now and then a look at what they are walking past.
		float g = fract(t * 0.07 + seed * 11.0);
		q.head.y += (smoothstep(0.0, 0.05, g) - smoothstep(0.18, 0.24, g)) * (fract(seed * 17.0) < 0.5 ? 0.9 : -0.9);
	} else if (id == P_RUN) {
		q = pose_stride(c, 0.8, 1.2, 0.9, 1.3);
		q.lean = 0.22;
		q.rise *= 0.4;
	} else if (id == P_SUNBATHE) {
		bool flip = fract(seed * 7.0) < 0.5;
		q.arm_l = vec3(0.0, flip ? 1.2 : 0.45, 0.1);
		q.arm_r = vec3(0.0, flip ? 0.45 : 1.2, 0.1);
		q.leg_l = flip ? vec2(0.9, 1.7) : vec2(0.0);
		q.leg_r = flip ? vec2(0.0) : vec2(0.9, 1.7);
		q.head = vec2(0.0);
		q.rise = 0.0;
		q.lean = 0.0;
		q.pitch = HALF_PI;
		q.shift = -0.9;
	} else if (id == P_COWER) {
		q.arm_l = vec3(0.0, 2.5, 0.4);
		q.arm_r = vec3(0.0, 2.5, 0.4);
		q.leg_l = vec2(0.7, 1.3);
		q.leg_r = vec2(0.7, 1.3);
		q.lean = 0.25;
		q.head = vec2(0.35, sin(t * 38.0 + ph) * 0.05);
		q.rise = -0.15;
	} else if (id == P_FLEE) {
		q = pose_stride(c, 0.85, 1.2, 0.0, 0.0);
		q.arm_l = vec3(0.0, 2.6 + sin(t * 14.0 + ph) * 0.35, 0.3);
		q.arm_r = vec3(0.0, 2.6 + cos(t * 13.0 + ph) * 0.35, 0.3);
		q.lean = 0.3;
		q.rise *= 0.4;
	} else if (id == P_FIGHT || id == P_AIM || id == P_AIM_LONG || id == P_AIM_SHOULDER) {
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
		if (id == P_FIGHT) {
			q.arm_l = vec3(1.0, 0.25, 1.9);
			q.arm_r = vec3(1.0, 0.25, 1.9);
			q.lean = 0.12;
		} else if (id == P_AIM) {
			q.arm_l = vec3(1.25, -0.35, 0.5);
			q.arm_r = vec3(1.5, 0.0, 0.05);
		} else if (id == P_AIM_LONG) {
			// Butt in the shoulder, the other hand out under the barrel.
			q.arm_r = vec3(0.95, -0.12, 0.6);
			q.arm_l = vec3(1.4, -0.5, 0.3);
			q.lean = 0.1;
			q.head = vec2(0.08, 0.12);
		} else {
			// The tube up on the shoulder, steadied from underneath.
			q.arm_r = vec3(1.2, 0.1, 0.4);
			q.arm_l = vec3(1.55, -0.45, 0.7);
			q.lean = -0.04;
		}
	} else if (id == P_DANCE) {
		// Samba: quick feet, loose hips, arms out.
		float b = t * 9.0 + ph;
		q.arm_l = vec3(0.6 + sin(b) * 0.5, 1.1 + sin(b * 0.5) * 0.5, 1.2);
		q.arm_r = vec3(0.6 - sin(b) * 0.5, 1.1 - sin(b * 0.5) * 0.5, 1.2);
		q.leg_l = vec2(sin(b) * 0.35, 0.3 + max(0.0, sin(b)) * 0.6);
		q.leg_r = vec2(-sin(b) * 0.35, 0.3 + max(0.0, -sin(b)) * 0.6);
		q.spread = 0.1;
		q.lean = sin(b * 0.5) * 0.12;
		q.head = vec2(0.0, sin(b * 0.5) * 0.3);
		q.rise = -0.04 + abs(sin(b)) * 0.06;
	} else if (id == P_CHEER) {
		q = pose_cheer(t, ph);
	} else if (id == P_RIDE) {
		// Astride a motorbike, reaching for the bars.
		q.arm_l = vec3(1.15, 0.12, 0.25);
		q.arm_r = vec3(1.15, 0.12, 0.25);
		q.leg_l = vec2(1.0, 1.35);
		q.leg_r = vec2(1.0, 1.35);
		q.spread = 0.32;
		q.lean = 0.3;
		q.head = vec2(-0.25, 0.0);
		q.rise = 0.08;
	} else if (id == P_DRUM) {
		q = pose_stride(c, 0.3, 0.4, 0.0, 0.0);
		float b = t * 12.0 + ph;
		q.arm_l = vec3(0.7 + max(0.0, sin(b)) * 0.5, 0.2, 1.3);
		q.arm_r = vec3(0.7 + max(0.0, -sin(b)) * 0.5, 0.2, 1.3);
	} else if (id == P_JUMP) {
		q.arm_l = vec3(0.3, 1.0, 0.4);
		q.arm_r = vec3(0.3, 1.0, 0.4);
		q.leg_l = vec2(0.6, 1.0);
		q.leg_r = vec2(-0.2, 0.8);
	} else if (id == P_SLIDE) {
		// Feet first, leaning back on one arm.
		q.arm_l = vec3(-0.5, 0.5, 0.3);
		q.arm_r = vec3(0.4, 0.9, 0.5);
		q.leg_l = vec2(0.3, 0.1);
		q.leg_r = vec2(0.9, 1.2);
		q.lean = 0.4;
		q.head = vec2(0.6, 0.0);
		q.pitch = 1.0;
	} else if (id == P_DIVE) {
		// Flat out, arms stretched ahead.
		q.arm_l = vec3(2.9, 0.15, 0.1);
		q.arm_r = vec3(2.9, 0.15, 0.1);
		q.leg_l = vec2(-0.1, 0.15);
		q.leg_r = vec2(-0.25, 0.4);
		q.head = vec2(-0.5, 0.0);
		q.rise = 0.25;
		q.pitch = -1.25;
		q.shift = 0.5;
	} else if (id == P_DEAD || id == P_DOWN || id == P_KO || id == P_TACKLED) {
		// Sprawled: the dead and the tackled on their faces, the rest on their backs.
		bool face = id == P_DEAD || id == P_TACKLED;
		q = Pose(vec3(0.0, 2.4, 0.3), vec3(0.0, 1.3, 0.6), vec2(0.0, 0.2), vec2(0.0, 0.6),
				0.25, 0.0, vec2(0.0, 0.9), 0.0, face ? -HALF_PI : HALF_PI, 0.0, 0.0);
		if (id == P_KO) {
			// Out cold, breathing.
			q.arm_l = vec3(0.0, 1.5, 0.3);
			q.arm_r = vec3(0.0, 0.7, 0.9);
			q.lean = sin(t * 1.6 + ph) * 0.03;
		}
	} else if (id == P_HANDS_UP) {
		q.arm_l = vec3(0.0, 2.6, 0.5);
		q.arm_r = vec3(0.0, 2.6, 0.5);
		q.head = vec2(0.1, 0.0);
	} else if (id == P_CALL) {
		// Phone to the ear, glancing about.
		q.arm_r = vec3(0.5, 0.45, 2.45);
		q.arm_l = vec3(0.4, -0.3, 1.6);
		q.head = vec2(0.05, 0.25 + sin(t * 1.7 + ph) * 0.3);
	} else if (id == P_DRINK || id == P_EAT) {
		// The hand comes up to the mouth every few seconds.
		float f = fract(t * (id == P_EAT ? 0.4 : 0.22) + seed * 9.0);
		float lift = smoothstep(0.0, 0.1, f) * (1.0 - smoothstep(0.22, 0.34, f));
		q.arm_r = vec3(0.35 + lift * 0.55, 0.1, 1.2 + lift * 1.15);
		q.arm_l = vec3(0.1, 0.07, 0.3);
		q.head.x = -0.22 * lift * (id == P_EAT ? -0.6 : 1.0);
		q.head.y *= 1.0 - lift;
	} else if (id == P_TALK) {
		// The one talking waves their hands about; the rest nod along.
		float g = clamp(speed, 0.0, 1.0);
		q.arm_l = mix(q.arm_l, vec3(0.75 + sin(t * 3.1 + ph) * 0.3, 0.25 + sin(t * 2.3 + ph) * 0.2, 1.3 + sin(t * 4.3 + ph) * 0.35), g);
		q.arm_r = mix(q.arm_r, vec3(0.75 + cos(t * 2.7 + ph) * 0.3, 0.25 + cos(t * 3.4 + ph) * 0.2, 1.3 + cos(t * 3.9 + ph) * 0.35), g);
		q.head = vec2(sin(t * (3.0 + g * 3.0) + ph) * 0.08, sin(t * 0.9 + ph) * 0.12);
		q.lean = 0.04 * g;
	} else if (id == P_PHONE) {
		// Thumbing a message, head down.
		q.arm_l = vec3(0.6, -0.2, 1.5);
		q.arm_r = vec3(0.6, -0.2, 1.5 + sin(t * 9.0 + ph) * 0.04);
		q.head = vec2(0.5, 0.0);
	} else if (id == P_SELFIE) {
		q.arm_r = vec3(2.0, -0.2, 0.25);
		q.arm_l = vec3(0.3, 0.9, 2.3);
		q.head = vec2(-0.2, 0.15);
		q.lean = -0.06;
	} else if (id == P_DIG) {
		float b = t * 3.4 + ph;
		float dig = sin(b);
		q.arm_l = vec3(0.75 + dig * 0.45, 0.0, 0.5 - dig * 0.3);
		q.arm_r = vec3(0.95 + dig * 0.45, 0.0, 0.7 - dig * 0.3);
		q.leg_l = vec2(0.45, 0.6);
		q.leg_r = vec2(-0.2, 0.45);
		q.lean = 0.65 + dig * 0.2;
		q.head = vec2(0.2, 0.0);
		q.rise = -0.07;
	} else if (id == P_KEEPUP) {
		// On the toes, arms out, waiting for the ball.
		float b = t * 5.0 + ph;
		q.arm_l = vec3(0.2, 0.55 + sin(b) * 0.1, 0.6);
		q.arm_r = vec3(0.2, 0.55 - sin(b) * 0.1, 0.6);
		q.leg_l = vec2(0.1, 0.25 + max(0.0, sin(b)) * 0.2);
		q.leg_r = vec2(0.1, 0.25 + max(0.0, -sin(b)) * 0.2);
		q.head = vec2(-0.25, 0.0);
		q.rise = -0.03 + abs(sin(b)) * 0.04;
	} else if (id == P_LEAN) {
		// Back to the wall, one foot up on it, arms folded.
		q.arm_l = vec3(0.6, -0.4, 1.9);
		q.arm_r = vec3(0.5, -0.4, 1.9);
		q.leg_r = vec2(0.55, 1.5);
		q.lean = -0.08;
		q.pitch = 0.12;
		q.head = vec2(0.1, sin(t * 0.4 + ph) * 0.5);
	} else if (id == P_SQUAT) {
		q.arm_l = vec3(1.1, 0.1, 0.5);
		q.arm_r = vec3(1.1, 0.1, 0.5);
		q.leg_l = vec2(1.75, 2.4);
		q.leg_r = vec2(1.75, 2.4);
		q.spread = 0.25;
		q.lean = 0.45;
		q.rise = -0.5;
	} else if (id == P_CROUCH) {
		// Low and quiet. Creeps when moving.
		float s = sin(c) * min(speed, 1.0);
		q.arm_l = vec3(0.5 - s * 0.3, 0.15, 1.1);
		q.arm_r = vec3(0.5 + s * 0.3, 0.15, 1.1);
		q.leg_l = vec2(1.0 + s * 0.4, 1.7 + max(0.0, cos(c)) * 0.3 * min(speed, 1.0));
		q.leg_r = vec2(1.0 - s * 0.4, 1.7 + max(0.0, -cos(c)) * 0.3 * min(speed, 1.0));
		q.lean = 0.5;
		q.head = vec2(-0.35, 0.0);
		q.rise = -0.33;
	} else if (id == P_GINGA) {
		// Capoeira: rocking back and across, guard arm swinging over the face.
		float b = t * 3.6 + ph;
		float s = sin(b);
		q.arm_l = vec3(1.0, 0.3 + max(0.0, s) * 0.5, 1.6 - max(0.0, s) * 0.8);
		q.arm_r = vec3(1.0, 0.3 + max(0.0, -s) * 0.5, 1.6 - max(0.0, -s) * 0.8);
		q.leg_l = vec2(0.5 - max(0.0, s) * 1.1, 0.7);
		q.leg_r = vec2(0.5 - max(0.0, -s) * 1.1, 0.7);
		q.spread = 0.3;
		q.lean = 0.3;
		q.head = vec2(-0.2, s * 0.2);
		q.rise = -0.16 + abs(cos(b)) * 0.05;
	} else if (id == P_CLAP) {
		float b = abs(sin(t * 6.0 + ph));
		q.arm_l = vec3(0.9, -0.35 + b * 0.3, 1.3);
		q.arm_r = vec3(0.9, -0.35 + b * 0.3, 1.3);
		q.rise = b * 0.02;
		q.head = vec2(0.0, sin(t * 3.0 + ph) * 0.15);
	} else if (id == P_LIFT) {
		// Pressing a bar overhead.
		float b = 0.5 + 0.5 * sin(t * 2.2 + ph);
		q.arm_l = vec3(0.0, 1.5 + b * 1.3, 1.6 - b * 1.5);
		q.arm_r = vec3(0.0, 1.5 + b * 1.3, 1.6 - b * 1.5);
		q.leg_l = vec2(0.15, 0.3);
		q.leg_r = vec2(0.15, 0.3);
		q.spread = 0.14;
		q.head = vec2(-0.1, 0.0);
		q.brow = 1.0 - b;
	} else if (id == P_WORK) {
		// Hammering at a bench.
		float b = abs(sin(t * 4.5 + ph));
		q.arm_r = vec3(0.7 + b * 0.8, 0.1, 1.2 - b * 0.5);
		q.arm_l = vec3(0.8, -0.1, 0.9);
		q.lean = 0.3;
		q.head = vec2(0.35, 0.0);
	} else if (id == P_WAVE) {
		// An arm up, flapping at somebody across the way.
		float w = sin(t * 9.0 + ph);
		q.arm_r = vec3(0.1, 2.5 + w * 0.3, 0.45 - w * 0.3);
		q.head = vec2(-0.1, 0.0);
		q.rise += abs(w) * 0.015;
	} else if (id == P_POINT) {
		q.arm_r = vec3(1.5 + sin(t * 5.0 + ph) * 0.05, 0.2, 0.05);
		q.arm_l = vec3(-0.25, 0.6, 1.5);
		q.lean = 0.07;
		q.head = vec2(-0.05, -0.15);
	} else if (id == P_ARGUE) {
		// Up on the toes, a finger in the other one's face.
		float j = max(0.0, sin(t * 6.5 + ph));
		q.arm_r = vec3(1.25 + j * 0.3, 0.1, 0.7 - j * 0.55);
		q.arm_l = vec3(0.5 + sin(t * 4.1 + ph) * 0.4, 0.5 + sin(t * 2.9 + ph) * 0.3, 1.2);
		q.leg_l = vec2(0.3, 0.3);
		q.leg_r = vec2(-0.2, 0.2);
		q.lean = 0.16 + j * 0.08;
		q.head = vec2(-0.05 + sin(t * 11.0 + ph) * 0.07, sin(t * 3.0 + ph) * 0.15);
		q.brow = 1.0;
		q.rise = j * 0.02;
	} else if (id == P_SHRUG) {
		float b = 0.5 + 0.5 * sin(t * 2.2 + ph);
		q.arm_l = vec3(0.35, 0.45 + b * 0.35, 1.5);
		q.arm_r = vec3(0.35, 0.45 + b * 0.35, 1.5);
		q.head = vec2(-0.05, sin(t * 2.2 + ph) * 0.3);
		q.rise = b * 0.012;
	} else if (id == P_LAUGH) {
		// Head back, holding the belly, shaking with it.
		float b = abs(sin(t * 10.0 + ph));
		float roll = 0.5 + 0.5 * sin(t * 1.1 + ph);
		q.arm_l = vec3(0.55, -0.35, 1.75);
		q.arm_r = vec3(0.5, -0.35, 1.8);
		q.lean = mix(-0.18, 0.3, roll) + b * 0.03;
		q.head = vec2(mix(-0.45, 0.25, roll), 0.0);
		q.rise = b * 0.02;
	} else if (id == P_STRETCH) {
		// Up on the toes with the arms overhead, then down to touch them.
		float f = sin(t * 0.8 + ph);
		float up = smoothstep(-0.2, 0.4, f);
		q.arm_l = mix(vec3(1.5, 0.05, 0.05), vec3(0.0, 2.95 + sin(t * 1.6) * 0.1, 0.1), up);
		q.arm_r = mix(vec3(1.5, 0.05, 0.05), vec3(0.0, 2.95 - sin(t * 1.6) * 0.1, 0.1), up);
		q.lean = mix(1.25, -0.1, up);
		q.head = vec2(mix(0.4, -0.2, up), 0.0);
		q.rise = up * 0.03;
	} else if (id == P_PUSHUP) {
		float b = 0.5 + 0.5 * sin(t * 3.0 + ph);
		q.arm_l = vec3(1.45, 0.3, 1.4 * (1.0 - b));
		q.arm_r = vec3(1.45, 0.3, 1.4 * (1.0 - b));
		q.leg_l = vec2(0.0);
		q.leg_r = vec2(0.0);
		q.head = vec2(-0.5, 0.0);
		q.lean = 0.0;
		q.rise = 0.0;
		q.pitch = -1.26 - (1.0 - b) * 0.2;
		q.brow = 1.0 - b;
	} else if (id == P_SMOKE) {
		// A long drag, then the hand back down by the side.
		float f = fract(t * 0.16 + seed * 9.0);
		float lift = smoothstep(0.0, 0.08, f) * (1.0 - smoothstep(0.2, 0.3, f));
		q.arm_r = vec3(0.3 + lift * 0.5, 0.12, 0.5 + lift * 1.85);
		q.arm_l = vec3(0.5, -0.4, 1.8);
		q.head.x = -0.25 * smoothstep(0.26, 0.34, f) * (1.0 - smoothstep(0.42, 0.5, f));
	} else if (id == P_YAWN) {
		float f = fract(t * 0.12 + seed * 5.0);
		float y = smoothstep(0.0, 0.1, f) * (1.0 - smoothstep(0.3, 0.42, f));
		q.arm_l = mix(q.arm_l, vec3(0.0, 2.3, 1.1), y);
		q.arm_r = mix(q.arm_r, vec3(0.55, 0.35, 2.45), y);
		q.head.x = mix(q.head.x, -0.35, y);
		q.lean -= 0.1 * y;
	} else if (id == P_LOOK) {
		// A hand over the eyes, looking one way and then the other.
		float turn = clamp(sin(t * 0.9 + ph) * 2.2, -1.0, 1.0);
		q.arm_r = vec3(0.55, 0.85, 2.3);
		q.head = vec2(-0.05, turn * 1.0);
		q.lean = 0.06;
		q.rise = 0.02;
	} else if (id == P_TIE) {
		// Down on one knee over a shoe.
		q.arm_l = vec3(1.05, -0.1, 0.5 + sin(t * 6.0 + ph) * 0.08);
		q.arm_r = vec3(1.05, -0.1, 0.5 - sin(t * 6.0 + ph) * 0.08);
		q.leg_l = vec2(1.55, 1.6);
		q.leg_r = vec2(-0.1, 1.65);
		q.lean = 0.75;
		q.head = vec2(0.45, 0.0);
		q.rise = -0.41;
	} else if (id == P_HUG) {
		// Arms round somebody, turning slowly on the spot.
		float b = sin(t * 1.4 + ph);
		q.arm_l = vec3(1.3, -0.4, 0.95);
		q.arm_r = vec3(1.3, -0.4, 0.95);
		q.leg_l = vec2(b * 0.12, 0.12 + max(0.0, b) * 0.2);
		q.leg_r = vec2(-b * 0.12, 0.12 + max(0.0, -b) * 0.2);
		q.lean = 0.12;
		q.head = vec2(0.2, 0.55);
	} else if (id == P_BEG) {
		// Hunched, one hand held out.
		q.arm_r = vec3(1.1 + sin(t * 2.0 + ph) * 0.08, 0.1, 0.45);
		q.arm_l = vec3(0.5, -0.4, 1.8);
		q.leg_l = vec2(0.25, 0.4);
		q.leg_r = vec2(0.25, 0.4);
		q.lean = 0.28;
		q.head = vec2(-0.1, sin(t * 0.7 + ph) * 0.5);
		q.rise = -0.04;
	} else if (id == P_STAGGER) {
		// Two steps forward and one to the side.
		float w = sin(t * 1.3 + ph);
		q = pose_stride(c * 0.7, 0.35, 0.5, 0.0, 0.0);
		q.arm_l = vec3(sin(t * 1.7 + ph) * 0.5, 0.35 + w * 0.3, 0.5);
		q.arm_r = vec3(cos(t * 1.5 + ph) * 0.5, 0.35 - w * 0.3, 0.5);
		q.spread = 0.1 + abs(w) * 0.12;
		q.lean = 0.12 + w * 0.22;
		q.head = vec2(0.25 + w * 0.2, sin(t * 0.8 + ph) * 0.6);
	} else if (id == P_TEXT_WALK) {
		q = pose_stride(c, 0.4 * gait, 0.55, 0.0, 0.0);
		q.arm_l = vec3(0.6, -0.2, 1.5);
		q.arm_r = vec3(0.6, -0.2, 1.5 + sin(t * 9.0 + ph) * 0.04);
		q.head = vec2(0.5, 0.0);
	} else if (id == P_LIMP) {
		// One leg that will not bend, a hand clamped to the side.
		float s = sin(c * 0.8);
		q = pose_stride(c * 0.8, 0.3, 0.5, 0.2, 0.3);
		q.leg_r = vec2(-s * 0.12, 0.05);
		q.arm_l = vec3(0.45, -0.35, 1.75);
		q.lean = 0.2 + max(0.0, s) * 0.12;
		q.head = vec2(0.3, 0.0);
		q.rise = -abs(s) * 0.05;
		q.brow = 1.0;
	} else if (id == P_CRAWL) {
		// Face down, dragging along on the elbows.
		float s = sin(c * 0.7);
		q.arm_l = vec3(2.5 + s * 0.45, 0.35, 0.9 - s * 0.5);
		q.arm_r = vec3(2.5 - s * 0.45, 0.35, 0.9 + s * 0.5);
		q.leg_l = vec2(0.0, 0.3 + max(0.0, s) * 0.9);
		q.leg_r = vec2(0.0, 0.3 + max(0.0, -s) * 0.9);
		q.spread = 0.18;
		q.lean = 0.0;
		q.head = vec2(-0.45, s * 0.25);
		q.rise = 0.0;
		q.pitch = -1.42;
		q.shift = 0.4;
	} else if (id == P_SCREAM) {
		// Hands to the face, knees going, backing off.
		q.arm_l = vec3(0.75, 0.45, 2.5);
		q.arm_r = vec3(0.75, 0.45, 2.5);
		q.leg_l = vec2(0.2, 0.45);
		q.leg_r = vec2(-0.05, 0.35);
		q.lean = -0.14;
		q.head = vec2(-0.3, sin(t * 31.0 + ph) * 0.07);
		q.rise = -0.06 + sin(t * 27.0 + ph) * 0.008;
	} else if (id == P_PANIC) {
		// Running with a look back over the shoulder, one arm windmilling.
		q = pose_stride(c, 0.85, 1.2, 0.9, 1.2);
		float back = fract(seed * 29.0) < 0.5 ? 1.0 : -1.0;
		float g = smoothstep(0.2, 0.4, fract(t * 0.45 + seed * 7.0)) * (1.0 - smoothstep(0.6, 0.8, fract(t * 0.45 + seed * 7.0)));
		q.arm_l = vec3(sin(t * 12.0 + ph) * 1.2, 1.3, 0.5);
		q.head = vec2(0.0, 1.3 * back * g);
		q.lean = 0.34;
		q.rise *= 0.4;
	} else if (id == P_SWEEP) {
		float w = sin(t * 2.6 + ph);
		q.arm_l = vec3(0.75 + w * 0.3, -0.1, 0.7);
		q.arm_r = vec3(0.95 - w * 0.25, -0.2, 0.95);
		q.leg_l = vec2(0.2 + w * 0.08, 0.2);
		q.leg_r = vec2(-0.15, 0.15);
		q.lean = 0.3 + w * 0.05;
		q.head = vec2(0.35, w * 0.1);
	} else if (id == P_PHOTO) {
		// Both hands up to the face, framing it, knees bending for the angle.
		float b = 0.5 + 0.5 * sin(t * 0.7 + ph);
		q.arm_l = vec3(1.25, -0.3, 1.85);
		q.arm_r = vec3(1.25, -0.3, 1.85);
		q.leg_l = vec2(0.2, 0.2 + b * 0.5);
		q.leg_r = vec2(0.2, 0.2 + b * 0.5);
		q.lean = 0.06 + b * 0.1;
		q.head = vec2(0.05, 0.0);
		q.rise = -b * 0.1;
	} else if (id == P_FILM) {
		// A phone held up and out at arm's length, to get all of it.
		q.arm_r = vec3(1.75 + sin(t * 1.9 + ph) * 0.04, 0.05, 0.5);
		q.arm_l = vec3(0.3, 0.1, 0.4);
		q.lean = -0.05;
		q.head = vec2(-0.12, 0.0);
	} else if (id == P_PREACH) {
		// Arms wide to the heavens, then a finger at the sinners.
		float b = 0.5 + 0.5 * sin(t * 1.1 + ph);
		q.arm_l = vec3(0.3, 1.3 + b * 0.9, 0.5);
		q.arm_r = mix(vec3(0.3, 1.3 + b * 0.9, 0.5), vec3(1.5, 0.2, 0.1), smoothstep(0.55, 0.8, fract(t * 0.13 + seed)));
		q.lean = -0.08 + b * 0.12;
		q.head = vec2(-0.25 * b, sin(t * 0.6 + ph) * 0.5);
		q.rise = b * 0.02;
		q.brow = 0.6;
	}
	if (seated) {
		if (id == P_SIT) {
			q.arm_l = vec3(0.5, 0.1, 0.6);
			q.arm_r = vec3(0.5, 0.1, 0.6);
		}
		q.leg_l = vec2(1.45, 1.5);
		q.leg_r = vec2(1.45, 1.5);
		q.spread = 0.12;
		q.rise = -0.36;
		q.lean = 0.0;
	}
	return q;
}

bool lying(int id) {
	return id == P_SUNBATHE || id == P_DEAD || id == P_DOWN || id == P_KO || id == P_TACKLED || id == P_PUSHUP || id == P_CRAWL;
}

bool prop_shown(int prop, int flags, int held, int pose) {
	if (prop == 0) {
		return true;
	}
	if (prop >= PROP_HELD) {
		return held == prop - PROP_HELD;
	}
	if (prop < PROP_CUP) {
		return (flags & (1 << (prop - 1))) != 0;
	}
	if (prop == PROP_CUP) {
		return pose == P_DRINK || pose == P_SIT_DRINK;
	}
	if (prop == PROP_PHONE) {
		return pose == P_PHONE || pose == P_SIT_PHONE || pose == P_SELFIE || pose == P_CALL || pose == P_TEXT_WALK || pose == P_PHOTO || pose == P_FILM;
	}
	return prop == PROP_SPADE && (pose == P_DIG || pose == P_SWEEP);
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
	int word = int(cd.x + 0.5);
	int pose = word & 63;
	int prev = (word >> 6) & 63;
	float speed = float((word >> 12) & 63) * 0.2;
	int held = (word >> 18) & 31;
	int flags = int(cd.z + 0.5);
	int part = int(partf + 0.5);
	int prop = int(propf + 0.5);
	dead_k = 0.0;
	hit_k = 0.0;
	if (!prop_shown(prop, flags, held, pose)) {
		// Prop not worn: fold it into a point inside the chest. A zero normal keeps the outline off it.
		p = vec3(0.0, 1.05, 0.0);
		n = vec3(0.0);
		return;
	}

	float t = now;
	float ph = seed * 19.0;
	float ev = cd.w;
	float atk = ev > 0.0 ? t - ev : 99.0;
	float hit = ev < 0.0 ? t + ev : 99.0;
	bool gun = held >= HELD_GUN && held <= HELD_LAUNCHER;
	bool two_hands = held >= HELD_LONG && held <= HELD_LAUNCHER;

	// How far the change from the previous pose has got. Falling over takes longer and starts slow.
	float k = smoothstep(0.0, lying(pose) || lying(prev) ? 0.45 : 0.22, t - cd.y);
	if (lying(pose)) {
		k *= k;
	}

	Pose q;
	float squash = 0.0;
	if (rigged) {
		q = Pose(rig0.xyz, rig1.xyz, rig2.xy, rig2.zw, rig0.w, rig1.w, rig3.xy, rig3.z, rig3.w, rig4.x, rig4.y);
		squash = rig4.z;
	} else {
		q = pose_for(pose, speed, t, ph, seed);
		if (cheer > 0.0 && (pose == 0 || pose == P_WALK || pose == P_DANCE) && fract(seed * 13.0) < 0.85) {
			q = pose_mix(q, pose_cheer(t, ph), cheer);
		}
		if (pose != P_AIM && pose != P_AIM_LONG && pose != P_AIM_SHOULDER && !lying(pose)) {
			// Anyone carrying a pistol holds it out in front; a rifle goes across the body,
			// muzzle down; a blade stays low and ready.
			if (two_hands) {
				q.arm_r = vec3(0.35, -0.1, 0.9);
				q.arm_l = vec3(0.9, -0.55, 0.9);
			} else if (gun) {
				q.arm_r = vec3(1.45, 0.0, 0.05);
			} else if (held > 0) {
				q.arm_r = vec3(0.55, 0.15, 1.0);
			}
		}
		if (prev != pose && k < 1.0) {
			q = pose_mix(pose_for(prev, speed, t, ph, seed), q, k);
		}
	}

	// One-shots: punch, stab or recoil; a touch on the ball; flinching from a hit.
	float e = smoothstep(0.0, 0.07, atk) * (1.0 - smoothstep(0.1, 0.32, atk));
	if (pose == P_KEEPUP) {
		float kick = smoothstep(0.0, 0.12, atk) * (1.0 - smoothstep(0.16, 0.42, atk));
		bool knee = fract(ev * 7.3) < 0.5;
		q.leg_r = mix(q.leg_r, knee ? vec2(1.5, 1.6) : vec2(1.0, 0.35), kick);
		q.lean -= 0.1 * kick;
	} else if (gun) {
		q.arm_r.x += 0.45 * e;
		q.lean -= 0.08 * e;
	} else if (!lying(pose)) {
		q.arm_r = mix(q.arm_r, vec3(1.5, 0.0, 0.05), e);
		q.lean += 0.2 * e;
	}
	float flinch = 1.0 - smoothstep(0.0, 0.3, hit);
	hit_k = 1.0 - smoothstep(0.0, 0.14, hit);
	if (lying(pose)) {
		flinch *= 0.3;
	}
	q.lean -= 0.35 * flinch;
	q.head.x -= 0.4 * flinch;
	if (pose == P_DEAD) {
		dead_k = k;
		hit_k = 0.0;
	}

	if (part == PART_BROW_L || part == PART_BROW_R) {
		float side = part == PART_BROW_L ? -1.0 : 1.0;
		rz(p, n, vec3(side * 0.075, 1.67, -0.19), side * q.brow * 0.45);
		p.y -= q.brow * 0.02;
		part = PART_HEAD;
	}
	if (part == PART_HEAD) {
		vec3 neck = vec3(0.0, 1.4, 0.0);
		p = neck + (p - neck) * (1.0 + 0.9 * min(trip, 1.0) * (0.75 + 0.25 * sin(now * 2.0 + seed * 40.0)));
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
	// Squash and stretch on a hit or a landing, anchored at the feet.
	float sq = flinch * 0.1 + squash;
	p.y *= 1.0 - sq;
	p.xz *= 1.0 + sq * 0.6;
	rx(p, n, vec3(0.0), q.pitch);
	p.y += abs(sin(q.pitch)) * 0.17;
	// Centre a lying body on its spot instead of hinging at the feet.
	p.z += q.shift;
}
