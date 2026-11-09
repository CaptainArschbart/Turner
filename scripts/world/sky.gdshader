shader_type sky;
// Himmel über dem Hof: Verlauf, Sonnen- bzw. Mondscheibe mit Hof, ziehende Wolken und Sterne bei Nacht.
// Farben und Anteile setzt DayCycle je nach Uhrzeit.

uniform vec3 top_color : source_color = vec3(0.24, 0.45, 0.78);
uniform vec3 horizon_color : source_color = vec3(0.68, 0.80, 0.92);
uniform vec3 ground_color : source_color = vec3(0.30, 0.31, 0.32);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.85);
uniform vec3 cloud_color : source_color = vec3(1.0);
uniform float sun_size = 0.9995;      // cos des Scheibenradius
uniform float sun_glow = 0.4;
uniform float stars = 0.0;            // 0 = Tag, 1 = volle Nacht
uniform float cloud_cover = 0.45;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);          // Richtung zur Sonne, auch unter dem Horizont
uniform float twilight = 0.0;                        // Stärke von Abendrot und blauer Stunde
uniform vec3 twilight_color : source_color = vec3(1.0, 0.5, 0.26);
uniform vec3 cloud_lit : source_color = vec3(0.0);   // Licht der tief stehenden Sonne an den Wolkenrändern

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(vec3(i, 0.0));
	float b = hash(vec3(i + vec2(1.0, 0.0), 0.0));
	float c = hash(vec3(i + vec2(0.0, 1.0), 0.0));
	float d = hash(vec3(i + vec2(1.0, 1.0), 0.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col = mix(horizon_color, top_color, pow(clamp(h, 0.0, 1.0), 0.45));
	if (h < 0.0) {
		col = mix(horizon_color, ground_color, clamp(-h * 4.0, 0.0, 1.0));
	}

	// Dämmerung: Glühen am Horizont auf der Seite der Sonne, auch wenn sie schon untergegangen ist
	vec3 flat_d = normalize(vec3(d.x, 0.0, d.z) + vec3(0.0001));
	vec3 flat_s = normalize(vec3(sun_dir.x, 0.0, sun_dir.z) + vec3(0.0001));
	float side = max(dot(flat_d, flat_s), 0.0);
	float band = exp(-max(h, 0.0) * 7.0) * step(-0.02, h);
	col += twilight_color * twilight * band * (pow(side, 3.0) * 0.9 + 0.12);
	// Gegendämmerung: auf der anderen Seite ein rosa Schimmer über dem Horizont
	col += vec3(0.5, 0.32, 0.45) * twilight * 0.18 * pow(max(-dot(flat_d, flat_s), 0.0), 2.0) * exp(-max(h - 0.08, 0.0) * 6.0) * step(0.0, h);

	if (AT_CUBEMAP_PASS == false && h > 0.0) {
		// Sterne: feste Punkte auf der Himmelskugel in leicht unterschiedlichen Farben, funkelnd,
		// dazu ein schwacher Milchstraßen-Schimmer
		if (stars > 0.01) {
			vec3 p = d * 420.0;
			vec3 cell = floor(p);
			float s = hash(cell);
			float r = length(fract(p) - 0.5);
			float tw = 0.65 + 0.35 * sin(TIME * (1.5 + s * 3.0) + s * 40.0);
			float bright = step(0.9965, s) * (0.4 + 0.6 * hash(cell + 7.0));
			float star = bright * smoothstep(0.32, 0.04, r) * tw * smoothstep(0.0, 0.25, h);
			vec3 tint = mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.88, 0.7), hash(cell + 3.0));
			col += tint * star * stars * 1.6;
			vec3 axis = normalize(vec3(0.35, 0.55, 0.76));
			float milky = exp(-pow(dot(d, axis) * 4.0, 2.0)) * fbm(d.xz * 9.0 + d.y * 3.0);
			col += vec3(0.55, 0.6, 0.8) * milky * 0.02 * stars * smoothstep(0.05, 0.4, h);
		}
	}

	if (LIGHT0_ENABLED) {
		float c = dot(d, LIGHT0_DIRECTION);
		float disc = smoothstep(sun_size, sun_size + 0.0003, c);
		float glow = pow(max(c, 0.0), 120.0) * sun_glow + pow(max(c, 0.0), 8.0) * sun_glow * 0.25;
		col += sun_color * (disc * 6.0 + glow) * LIGHT0_ENERGY * step(-0.05, h);
	}

	// Wolken auf einer gedachten Ebene über dem Hof
	if (h > 0.02) {
		vec2 uv = d.xz / (h + 0.12) * 1.6 + vec2(TIME * 0.006, TIME * 0.002);
		float n = fbm(uv);
		float cl = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.35, n);
		cl *= smoothstep(0.02, 0.2, h);
		vec3 cc = cloud_color * (0.75 + 0.25 * fbm(uv * 2.0 + 3.0));
		// Wolkenränder zur Sonne hin leuchten in der goldenen Stunde und im Abendrot
		float rim = pow(side, 2.0) * (1.0 - smoothstep(0.4, 0.9, cl)) * smoothstep(0.1, 0.4, cl);
		cc += cloud_lit * (rim * 1.2 + pow(side, 4.0) * 0.35);
		col = mix(col, cc, cl * 0.85);
	}
	COLOR = col;
}
