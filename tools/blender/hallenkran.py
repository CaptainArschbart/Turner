"""Erzeugt models/hallenkran.glb: Einträger-Brückenkran 5 t für die Werkstatthalle.

Aufruf (im Projektordner):
    blender -b --factory-startup --python tools/blender/hallenkran.py -- models/hallenkran.glb

Alle Maße in Metern und in Spielkoordinaten: x längs der Kranbahn (Brücke fährt), y nach oben,
z längs der Brücke (Katze fährt). Die Halle ist 24 x 16 m, die Kranbahnträger liegen bei z = +-7,4
mit Oberkante 5,475, die Dachträger beginnen bei 6,0.

Teile (je ein Objekt, Ursprung im Hallen-Nullpunkt, das Spiel verschiebt sie):
    Kranbahn      fest: Schienen, Konsolen an den Stützen, Endanschläge, Schleifleitung
    Bruecke       Kastenträger mit Kopfträgern, Fahrantrieben, Schaltschrank, Kabelschiene
    Katze         Einschienenkatze mit Seilzug; Lampe als eigenes Objekt (leuchtet mit Fernbedienung)
    Kabelwagen    ein Leitungswagen der Schleppleitung, Ursprung in der Schiene
    Unterflasche  Hakenflasche, Ursprung an der Hakenunterkante
    Gehaenge      Aufhängeglied des Kettengehänges, Ursprung an der Hakenunterkante
    Kettenglied   ein Glied der Kettenstränge, Ursprung in seiner Mitte
Leere Objekte markieren, wo das Spiel Seile und Schleppleitung anschließt.
"""
import math
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

# Spiel (x, y oben, z) -> Blender (x, -z, y oben)
TO_BLENDER = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
AXES = {"x": Vector((1, 0, 0)), "y": Vector((0, 1, 0)), "z": Vector((0, 0, 1))}
SHARP = math.radians(35.0)

BEAM_TOP = 5.475          # Oberkante Kranbahnträger
RAIL_TOP = BEAM_TOP + 0.03
RAIL_Z = 7.4
FLANGE_TOP = 5.365        # Oberkante Untergurt: Lauffläche der Katze
ROPE_X = 0.095            # Seilstränge links und rechts der Seilrolle
SHEAVE_Y = 0.343          # Mitte der Seilrolle über der Hakenunterkante
CABLE_X = 0.34            # Kabelschiene neben dem Träger
CABLE_RAIL_Y = 5.815
CABLE_DROP = 0.10         # so weit unter der Schiene liegt die Leitung im Sattel

# Name -> (Farbe sRGB, Rauheit, Metall)
MATS = {
    "Gelb": ((0.95, 0.72, 0.08), 0.5, 0.0),
    "Anthrazit": ((0.2, 0.22, 0.25), 0.5, 0.0),
    "Stahlblau": ((0.20, 0.28, 0.36), 0.55, 0.3),
    "Stahl": ((0.3, 0.3, 0.3), 0.4, 1.0),
    "Blank": ((0.62, 0.64, 0.66), 0.35, 1.0),
    "Zink": ((0.58, 0.6, 0.62), 0.5, 0.8),
    "Seil": ((0.24, 0.24, 0.25), 0.45, 0.9),
    "Haken": ((0.13, 0.13, 0.14), 0.5, 0.8),
    "Kette": ((0.11, 0.11, 0.12), 0.45, 0.8),
    "Schwarz": ((0.08, 0.08, 0.09), 0.6, 0.0),
    "Gummi": ((0.04, 0.04, 0.04), 0.9, 0.0),
    "Grau": ((0.76, 0.77, 0.75), 0.6, 0.0),
    "Kunststoff": ((0.5, 0.51, 0.5), 0.7, 0.0),
    "Blau": ((0.10, 0.27, 0.50), 0.45, 0.1),
    "Rot": ((0.72, 0.09, 0.07), 0.5, 0.0),
    "Schrift": ((0.07, 0.07, 0.07), 0.6, 0.0),
    "Lampe": ((0.1, 0.25, 0.12), 0.5, 0.0),
}


def lin(c):
    return tuple(v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in c)


def material(name):
    m = bpy.data.materials.get(name)
    if m:
        return m
    col, rough, metal = MATS[name]
    m = bpy.data.materials.new(name)
    if m.node_tree is None:
        m.use_nodes = True
    bsdf = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        bsdf = m.node_tree.nodes.new("ShaderNodeBsdfPrincipled")
        out = next((n for n in m.node_tree.nodes if n.type == "OUTPUT_MATERIAL"), None)
        if out is None:
            out = m.node_tree.nodes.new("ShaderNodeOutputMaterial")
        m.node_tree.links.new(bsdf.outputs[0], out.inputs[0])
    bsdf.inputs["Base Color"].default_value = (*lin(col), 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    m.diffuse_color = (*lin(col), 1.0)
    return m


class Part:
    """Ein Objekt des Modells: sammelt Körper in einem Netz, gebaut in Spielkoordinaten."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.mats = []
        self.soft = self.bm.faces.layers.int.new("soft")   # 1 = Kanten dieser Fläche immer weich
        self.markers = {}

    def mi(self, m):
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)

    def _face(self, verts, idx, soft=False):
        try:
            f = self.bm.faces.new(verts)
        except ValueError:
            return None
        f.material_index = idx
        if soft:
            f[self.soft] = 1
        return f

    def box(self, size, center, m, xf=None):
        """Quader. xf: 3x3-Drehung um die Mitte."""
        idx = self.mi(m)
        c = Vector(center)
        hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
        vs = []
        for sx, sy, sz in ((-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1), (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)):
            p = Vector((sx * hx, sy * hy, sz * hz))
            if xf is not None:
                p = xf @ p
            vs.append(self.bm.verts.new(c + p))
        for f in ((0, 1, 2, 3), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
            self._face([vs[i] for i in f], idx)

    def beam(self, p0, p1, su, sv, m, up=(1, 0, 0)):
        """Stab mit Rechteckquerschnitt von p0 nach p1 (sv in Richtung up, su quer dazu)."""
        p0, p1 = Vector(p0), Vector(p1)
        w = p1 - p0
        length = w.length
        w.normalize()
        u = Vector(up).cross(w)
        if u.length < 1e-6:
            u = Vector((0, 1, 0)).cross(w)
        u.normalize()
        v = w.cross(u)
        rot = Matrix((u, v, w)).transposed()
        self.box((su, sv, length), (p0 + p1) * 0.5, m, rot)

    def lathe(self, prof, center, axis, m, seg=24, soft=False):
        """Drehkörper: prof = [(Lage auf der Achse, Radius), ...]."""
        a = AXES[axis].copy() if isinstance(axis, str) else Vector(axis).normalized()
        ref = Vector((0, 1, 0)) if abs(a.y) < 0.9 else Vector((1, 0, 0))
        u = a.cross(ref).normalized()
        v = a.cross(u)
        c = Vector(center)
        idx = self.mi(m)
        rings = []
        for t, r in prof:
            rings.append([self.bm.verts.new(c + a * t + (u * math.cos(2 * math.pi * j / seg) + v * math.sin(2 * math.pi * j / seg)) * r)
                          for j in range(seg)])
        for k in range(len(rings) - 1):
            for j in range(seg):
                self._face((rings[k][j], rings[k][(j + 1) % seg], rings[k + 1][(j + 1) % seg], rings[k + 1][j]), idx, soft)
        self._face(rings[0], idx)
        self._face(list(reversed(rings[-1])), idx)

    def cyl(self, r, length, center, axis, m, seg=20, r2=None):
        self.lathe([(-length * 0.5, r), (length * 0.5, r if r2 is None else r2)], center, axis, m, seg)

    def hexbolt(self, center, axis, m="Zink", r=0.011, h=0.008):
        self.cyl(r, h, center, axis, m, 6)

    def prism(self, pts, origin, ea, eb, n0, n1, m):
        """Vieleck pts = [(a, b), ...] in der Ebene (ea, eb), ausgezogen entlang ea x eb von n0 bis n1."""
        o, ea, eb = Vector(origin), Vector(ea), Vector(eb)
        en = ea.cross(eb)
        idx = self.mi(m)
        lo = [self.bm.verts.new(o + ea * a + eb * b + en * n0) for a, b in pts]
        hi = [self.bm.verts.new(o + ea * a + eb * b + en * n1) for a, b in pts]
        n = len(pts)
        for i in range(n):
            self._face((lo[i], lo[(i + 1) % n], hi[(i + 1) % n], hi[i]), idx)
        self._face(lo, idx)
        self._face(list(reversed(hi)), idx)

    def sweep(self, pts, radii, normal, m, seg=10, closed=False):
        """Schlauch entlang der ebenen Kurve pts. radii = (quer zur Ebene, in der Ebene), auch je Punkt."""
        idx = self.mi(m)
        nrm = Vector(normal).normalized()
        pts = [Vector(p) for p in pts]
        n = len(pts)
        rings = []
        for i, p in enumerate(pts):
            if closed:
                t = pts[(i + 1) % n] - pts[i - 1]
            else:
                t = pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]
            t.normalize()
            side = t.cross(nrm).normalized()
            ra, rb = radii[i] if isinstance(radii, list) else radii
            rings.append([self.bm.verts.new(p + nrm * (ra * math.cos(2 * math.pi * j / seg)) + side * (rb * math.sin(2 * math.pi * j / seg)))
                          for j in range(seg)])
        for k in range(n if closed else n - 1):
            a, b = rings[k], rings[(k + 1) % n]
            for j in range(seg):
                self._face((a[j], a[(j + 1) % seg], b[(j + 1) % seg], b[j]), idx, True)
        if not closed:
            self._face(rings[0], idx)
            self._face(list(reversed(rings[-1])), idx)

    def link(self, center, along, normal, rc, straight, wire, m, seg=6, arc=5):
        """Kettenglied: Oval in der Ebene mit der Normalen normal, lange Achse along."""
        c, al, nr = Vector(center), Vector(along).normalized(), Vector(normal).normalized()
        side = nr.cross(al).normalized()
        pts = []
        for i in range(arc + 1):
            ang = math.pi * i / arc
            pts.append(c + al * (straight * 0.5 + rc * math.sin(ang)) + side * (rc * math.cos(ang)))
        for i in range(arc + 1):
            ang = math.pi * i / arc
            pts.append(c - al * (straight * 0.5 + rc * math.sin(ang)) - side * (rc * math.cos(ang)))
        self.sweep(pts, (wire, wire), nr, m, seg, True)

    def text(self, body, size, origin, right, up, m, depth=0.003):
        """Schrift als flaches Netz, Mitte bei origin, lesbar aus Richtung right x up."""
        cu = bpy.data.curves.new("schrift", "FONT")
        cu.body = body
        cu.size = size
        cu.align_x = "CENTER"
        cu.align_y = "CENTER"
        cu.extrude = depth * 0.5
        cu.resolution_u = 3
        ob = bpy.data.objects.new("schrift", cu)
        bpy.context.scene.collection.objects.link(ob)
        me = bpy.data.meshes.new_from_object(ob.evaluated_get(bpy.context.evaluated_depsgraph_get()))
        r, u = Vector(right).normalized(), Vector(up).normalized()
        n = r.cross(u)
        o = Vector(origin)
        idx = self.mi(m)
        vs = [self.bm.verts.new(o + r * v.co.x + u * v.co.y + n * (v.co.z + depth * 0.5)) for v in me.vertices]
        for p in me.polygons:
            self._face([vs[i] for i in p.vertices], idx)
        bpy.data.objects.remove(ob)
        bpy.data.curves.remove(cu)
        bpy.data.meshes.remove(me)

    def merge(self, other):
        """Zwischennetz (mit schon gesetzten Materialnummern) übernehmen."""
        me = bpy.data.meshes.new("tmp")
        other.to_mesh(me)
        other.free()
        self.bm.from_mesh(me)
        bpy.data.meshes.remove(me)

    def marker(self, name, pos):
        self.markers[name] = Vector(pos)

    def build(self):
        bm = self.bm
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        for f in bm.faces:
            f.smooth = True
        for e in bm.edges:
            fs = e.link_faces
            if len(fs) != 2:
                e.smooth = False
            elif fs[0][self.soft] and fs[1][self.soft]:
                e.smooth = True
            else:
                e.smooth = e.calc_face_angle(0.0) < SHARP
        tris = sum(len(f.verts) - 2 for f in bm.faces)
        bm.faces.layers.int.remove(self.soft)
        bm.transform(TO_BLENDER)
        me = bpy.data.meshes.new(self.name)
        bm.to_mesh(me)
        bm.free()
        for m in self.mats:
            me.materials.append(material(m))
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        for name, pos in self.markers.items():
            e = bpy.data.objects.new(name, None)
            e.empty_display_size = 0.05
            e.location = TO_BLENDER @ pos
            e.parent = ob
            bpy.context.scene.collection.objects.link(e)
        print("%-13s %6d Dreiecke, %d Materialien" % (self.name, tris, len(self.mats)))
        return ob


def carrier(p, pos):
    """Leitungswagen der Schleppleitung, pos = Mitte der Kabelschiene."""
    x, y, z = pos
    p.box((0.05, 0.02, 0.05), (x, y - 0.027, z), "Zink")
    p.box((0.008, 0.06, 0.04), (x, y - 0.065, z), "Zink")
    p.cyl(0.03, 0.05, (x, y - 0.105, z), "x", "Schwarz", 14)


def motor(p, center, axis, sign, r, length, m="Blau", fins=12):
    """Motor mit Kühlrippen und Lüfterhaube; center = Flanschmitte, er ragt nach sign * axis."""
    a = AXES[axis] * sign
    c = Vector(center)
    p.lathe([(0.0, r * 0.75), (0.0, r), (length, r), (length, r * 0.75)], c, a, m, 20)
    ref = Vector((0, 1, 0)) if axis != "y" else Vector((1, 0, 0))
    u = a.cross(ref).normalized()
    v = a.cross(u)
    for k in range(fins):
        ang = 2 * math.pi * k / fins
        d = u * math.cos(ang) + v * math.sin(ang)
        t = a.cross(d)
        rot = Matrix((d, t, a)).transposed()
        p.box((r * 0.16, r * 0.1, length * 0.82), c + a * (length * 0.5) + d * (r * 1.02), m, rot)
    p.lathe([(length, r * 0.6), (length, r * 1.06), (length + r * 0.75, r * 1.06), (length + r * 0.9, r * 0.8)], c, a, "Schwarz", 20)


# ------------------------------------------------------------------ Kranbahn

def kranbahn():
    k = Part("Kranbahn")
    for s in (-1, 1):
        z = s * RAIL_Z
        k.box((23.7, 0.03, 0.05), (0, BEAM_TOP + 0.015, z), "Stahl")                # Schiene
        x = -11.25
        while x < 11.3:                                                             # Klemmplatten
            for d in (-1, 1):
                k.box((0.07, 0.012, 0.045), (x, BEAM_TOP + 0.006, z + d * 0.05), "Stahlblau")
                k.hexbolt((x, BEAM_TOP + 0.016, z + d * 0.055), "y", "Zink", 0.009, 0.008)
            x += 1.5
        for e in (-1, 1):                                                           # Endanschläge mit Puffer
            k.box((0.16, 0.012, 0.22), (e * 11.915, BEAM_TOP + 0.006, z), "Stahlblau")
            k.box((0.02, 0.26, 0.2), (e * 11.93, BEAM_TOP + 0.13, z), "Stahlblau")
            k.prism([(e * 11.94, BEAM_TOP), (e * 11.997, BEAM_TOP), (e * 11.94, BEAM_TOP + 0.26)],
                    (0, 0, z), (1, 0, 0), (0, 1, 0), -0.008, 0.008, "Stahlblau")
            k.cyl(0.05, 0.06, (e * 11.89, 5.695, z), "x", "Gummi", 18)
        for x in (-11.86, -6.0, 0.0, 6.0, 11.86):                                   # Konsolen an den Stützen
            k.box((0.22, 0.2, 0.5), (x, BEAM_TOP - 0.45, s * 7.45), "Stahlblau")
            k.prism([(s * 7.66, 4.93), (s * 7.24, 4.93), (s * 7.66, 4.5)], (x, 0, 0), (0, 0, 1), (0, 1, 0), -0.011, 0.011, "Stahlblau")
            k.box((0.26, 0.012, 0.34), (x, BEAM_TOP - 0.346, s * 7.4), "Stahlblau")
    # Schleifleitung am nördlichen Kranbahnträger (Strom für die Brücke)
    zc = -7.205
    k.box((23.3, 0.075, 0.035), (0, 5.2, zc), "Kunststoff")
    k.box((23.3, 0.012, 0.045), (0, 5.2, zc), "Gelb")
    x = -11.0
    while x < 11.1:
        k.box((0.04, 0.03, 0.04), (x, 5.2, -7.235), "Zink")
        x += 2.0
    for e in (-1, 1):
        k.box((0.06, 0.09, 0.05), (e * 11.68, 5.2, zc), "Schwarz")
    return k.build()


# ------------------------------------------------------------------ Brücke

def bruecke():
    b = Part("Bruecke")
    # Kastenträger: Steg, Obergurt, Untergurt (Lauffläche der Katze)
    b.box((0.32, 0.53, 14.4), (0, 5.62, 0), "Gelb")
    b.box((0.38, 0.02, 14.4), (0, 5.89, 0), "Gelb")
    b.box((0.44, 0.025, 14.4), (0, FLANGE_TOP - 0.0125, 0), "Gelb")
    for s in (-1, 1):
        cz = s * RAIL_Z
        b.box((0.48, 0.58, 0.02), (0, 5.62, s * 7.205), "Gelb")                      # Stirnplatte
        b.box((0.40, 0.2, 0.0925), (0, 5.695, s * 7.25875), "Gelb")                  # Anschluss an den Kopfträger
        for bx in (-0.21, 0.21):
            for by in (5.44, 5.56, 5.68, 5.80):
                b.hexbolt((bx, by, s * 7.191), "z")
        for sx in (-1, 1):                                                           # Endpuffer für die Katze
            b.box((0.012, 0.075, 0.03), (sx * 0.19, FLANGE_TOP + 0.035, s * 7.05), "Gelb")
            b.cyl(0.022, 0.03, (sx * 0.19, FLANGE_TOP + 0.055, s * 7.03), "z", "Gummi", 12)
        # Kopfträger mit Laufrädern
        b.box((1.6, 0.22, 0.2), (0, 5.695, cz), "Gelb")
        for e in (-1, 1):
            b.box((0.012, 0.24, 0.22), (e * 0.806, 5.695, cz), "Gelb")
            b.cyl(0.045, 0.05, (e * 0.837, 5.695, cz), "x", "Gummi", 16)
            b.lathe([(-0.042, 0.06), (-0.042, 0.115), (-0.03, 0.115), (-0.03, 0.10), (0.03, 0.10), (0.03, 0.115), (0.042, 0.115), (0.042, 0.06)],
                    (e * 0.6, RAIL_TOP + 0.10, cz), "z", "Stahl", 28)
            for d in (-1, 1):                                                        # Radschilde mit Lagerdeckel
                zf = cz + d * 0.106
                b.prism([(-0.14, 5.74), (-0.14, 5.56), (-0.09, 5.53), (0.09, 5.53), (0.14, 5.56), (0.14, 5.74)],
                        (e * 0.6, 0, zf), (1, 0, 0), (0, 1, 0), -0.007, 0.007, "Gelb")
                b.cyl(0.05, 0.018, (e * 0.6, RAIL_TOP + 0.10, zf + d * 0.014), "z", "Anthrazit", 18)
                for k in range(4):
                    ang = math.pi / 4 + k * math.pi / 2
                    b.hexbolt((e * 0.6 + 0.038 * math.cos(ang), RAIL_TOP + 0.10 + 0.038 * math.sin(ang), zf + d * 0.026), "z", "Zink", 0.008, 0.006)
        # Fahrantrieb am Rad bei x = +0,6, Motor zur Hallenmitte
        zi = cz - s * 0.113
        b.box((0.13, 0.15, 0.11), (0.6, 5.62, zi - s * 0.055), "Blau")
        motor(b, (0.6, 5.635, zi - s * 0.11), "z", -s, 0.055, 0.19)
        b.box((0.07, 0.04, 0.08), (0.6, 5.705, zi - s * 0.2), "Blau")
    # Schleppleitung: Kabelschiene mit Auslegern, feste Endklemme im Norden
    b.box((0.034, 0.034, 14.3), (CABLE_X, CABLE_RAIL_Y, 0), "Zink")
    z = -6.3
    while z < 6.4:
        b.box((0.215, 0.012, 0.04), (0.2675, CABLE_RAIL_Y + 0.023, z), "Zink")
        b.box((0.012, 0.08, 0.04), (0.166, CABLE_RAIL_Y - 0.011, z), "Zink")
        z += 1.8
    carrier(b, (CABLE_X, CABLE_RAIL_Y, -7.12))
    b.box((0.06, 0.03, 0.02), (CABLE_X, CABLE_RAIL_Y - 0.027, -7.155), "Rot")
    # Schaltschrank an der Westseite, Nordende
    b.box((0.14, 0.30, 0.55), (-0.25, 5.73, -6.5), "Grau")
    b.box((0.006, 0.27, 0.5), (-0.323, 5.73, -6.5), "Grau")
    for dz in (-0.2, 0.2):
        b.box((0.03, 0.04, 0.04), (-0.17, 5.73, -6.5 + dz), "Gelb")
    b.box((0.004, 0.075, 0.075), (-0.328, 5.73, -6.66), "Gelb")
    b.cyl(0.024, 0.02, (-0.34, 5.73, -6.66), "x", "Rot", 14)
    b.box((0.012, 0.008, 0.05), (-0.352, 5.73, -6.66), "Rot")
    b.box((0.008, 0.05, 0.012), (-0.328, 5.73, -6.3), "Schwarz")
    # Stromabnehmer zur Schleifleitung
    b.box((0.03, 0.03, 0.115), (-0.45, 5.62, -7.2475), "Anthrazit")
    b.box((0.03, 0.37, 0.03), (-0.45, 5.45, -7.205), "Anthrazit")
    b.box((0.14, 0.05, 0.05), (-0.45, 5.258, -7.205), "Schwarz")
    # Tragfähigkeit auf beiden Seiten des Trägers, Typenschild
    b.text("5 t", 0.44, (0.1605, 5.60, 2.0), (0, 0, -1), (0, 1, 0), "Schrift")
    b.text("5 t", 0.44, (-0.1605, 5.60, -2.0), (0, 0, 1), (0, 1, 0), "Schrift")
    b.box((0.003, 0.11, 0.34), (0.1612, 5.60, -5.2), "Blank")
    b.text("HALLENKRAN  5000 kg", 0.026, (0.163, 5.618, -5.2), (0, 0, -1), (0, 1, 0), "Schrift", 0.001)
    b.text("Spannweite 14,8 m", 0.02, (0.163, 5.578, -5.2), (0, 0, -1), (0, 1, 0), "Schrift", 0.001)
    b.marker("Kabelschiene", (CABLE_X, CABLE_RAIL_Y, 0))
    b.marker("Kabel_Fest", (CABLE_X, CABLE_RAIL_Y - CABLE_DROP, -7.12))
    return b.build()


# ------------------------------------------------------------------ Katze

def katze():
    c = Part("Katze")
    wy = FLANGE_TOP + 0.055
    for sx in (-1, 1):
        for sz in (-1, 1):
            c.lathe([(0.0, 0.025), (0.0, 0.055), (0.05, 0.055), (0.05, 0.068), (0.06, 0.068), (0.06, 0.025)],
                    (sx * 0.172, wy, sz * 0.22), (sx, 0, 0), "Stahl", 20)
            c.cyl(0.015, 0.09, (sx * 0.215, wy, sz * 0.22), "x", "Stahl", 10)
            c.hexbolt((sx * 0.264, wy, sz * 0.22), "x", "Zink", 0.022, 0.02)
        # Seitenschild
        c.prism([(-0.34, 5.24), (0.34, 5.24), (0.34, 5.50), (0.30, 5.54), (-0.30, 5.54), (-0.34, 5.50)],
                (sx * 0.247, 0, 0), (0, 0, 1), (0, 1, 0), -0.007, 0.007, "Anthrazit")
    c.box((0.50, 0.014, 0.68), (0, 5.307, 0), "Anthrazit")                             # Traverse unter dem Träger
    # Seilzug: Trommel zwischen zwei Lagerschilden, Getriebe im Süden, Motor im Norden
    dx, dy = ROPE_X - 0.085, 5.215
    for sz in (-1, 1):
        c.box((0.36, 0.25, 0.015), (dx, 5.18, sz * 0.2375), "Anthrazit")
    prof = [(-0.229, 0.06), (-0.229, 0.10), (-0.219, 0.10), (-0.219, 0.081)]
    for i in range(39):
        t0 = -0.2145 + i * 0.011
        prof += [(t0, 0.0812), (t0 + 0.0055, 0.0855)]
    prof += [(0.2145, 0.0812), (0.219, 0.081), (0.219, 0.10), (0.229, 0.10), (0.229, 0.06)]
    c.lathe(prof, (dx, dy, 0), "z", "Seil", 28)
    c.box((0.26, 0.25, 0.13), (dx, 5.18, 0.31), "Blau")                                # Getriebe
    c.cyl(0.07, 0.02, (dx, dy, 0.384), "z", "Blau", 20)
    for k in range(6):
        ang = k * math.pi / 3
        c.hexbolt((dx + 0.055 * math.cos(ang), dy + 0.055 * math.sin(ang), 0.396), "z", "Zink", 0.008, 0.006)
    motor(c, (dx, dy, -0.245), "z", -1, 0.078, 0.23)
    c.box((0.05, 0.08, 0.10), (dx - 0.1, dy, -0.36), "Blau")
    # Seilfestpunkt am Rahmen
    c.box((0.03, 0.03, 0.46), (-ROPE_X - 0.015, 5.255, 0), "Anthrazit")
    c.box((0.024, 0.07, 0.024), (-ROPE_X, 5.205, 0), "Stahl")
    c.cyl(0.012, 0.03, (-ROPE_X, 5.16, 0), "y", "Stahl", 10)
    # Steuerkasten an der Westseite, darunter der Sockel der Meldeleuchte
    c.box((0.11, 0.22, 0.30), (-0.31, 5.19, 0.10), "Grau")
    c.box((0.006, 0.19, 0.26), (-0.368, 5.19, 0.10), "Grau")
    c.box((0.085, 0.04, 0.015), (-0.2125, 5.25, 0.2375), "Anthrazit")
    c.cyl(0.024, 0.016, (-0.31, 5.072, 0.10), "y", "Schwarz", 14)
    # Katzfahrantrieb
    c.box((0.07, 0.11, 0.11), (-0.29, wy, 0.22), "Blau")
    motor(c, (-0.29, wy + 0.01, 0.165), "z", -1, 0.04, 0.13)
    # Mitnehmer der Schleppleitung an der Ostseite, mit dem letzten Leitungswagen
    c.box((0.125, 0.012, 0.04), (0.3125, 5.50, 0.14), "Anthrazit")
    c.box((0.012, 0.25, 0.04), (0.369, 5.62, 0.14), "Anthrazit")
    c.box((0.03, 0.012, 0.03), (0.355, 5.74, 0.13), "Anthrazit")
    carrier(c, (CABLE_X, CABLE_RAIL_Y, 0.10))
    c.marker("Seil_Trommel", (ROPE_X, dy, 0))
    c.marker("Seil_Festpunkt", (-ROPE_X, 5.15, 0))
    c.marker("Kabel_Katze", (CABLE_X, CABLE_RAIL_Y - CABLE_DROP, 0.10))
    ob = c.build()
    # Meldeleuchte: eigene Halbkugel, das Spiel schaltet ihr Material
    lamp = Part("Lampe")
    lamp.lathe([(0.0, 0.028), (0.011, 0.0258), (0.02, 0.0196), (0.026, 0.0105), (0.028, 0.003)], (-0.31, 5.064, 0.10), (0, -1, 0), "Lampe", 16, True)
    lamp.build()
    return ob


# ------------------------------------------------------------------ Unterflasche und Gehänge

def hook_path():
    """Mittellinie des Hakens in der Ebene x = 0: [(z, y, Radius quer, Radius in der Ebene), ...]."""
    pts = [(0.0, 0.245, 0.019, 0.019), (0.0, 0.19, 0.019, 0.019), (0.0, 0.152, 0.019, 0.02)]
    cz, cy, rad = 0.0, 0.076, 0.053
    a0 = math.radians(150.0)
    p0 = Vector((0.0, 0.152))
    p3 = Vector((cz + rad * math.cos(a0), cy + rad * math.sin(a0)))
    t3 = Vector((-math.sin(a0), math.cos(a0)))
    p1 = p0 + Vector((0.0, -0.024))
    p2 = p3 - t3 * 0.022
    for k in range(1, 6):
        t = k / 6.0
        p = p0 * (1 - t) ** 3 + p1 * 3 * t * (1 - t) ** 2 + p2 * 3 * t * t * (1 - t) + p3 * t ** 3
        pts.append((p.x, p.y, 0.019 + 0.001 * t, 0.02 + 0.003 * t))
    for deg in range(150, 331, 10):
        a = math.radians(deg)
        pts.append((cz + rad * math.cos(a), cy + rad * math.sin(a), 0.02, 0.023))
    for deg in (340, 350, 360, 370, 380, 390, 398):
        a = math.radians(deg)
        f = (deg - 330) / 68.0
        pts.append((cz + rad * math.cos(a), cy + rad * math.sin(a), 0.02 - 0.011 * f, 0.023 - 0.014 * f))
    a = math.radians(398)
    tip = Vector((cz + rad * math.cos(a), cy + rad * math.sin(a))) + Vector((-math.sin(a), math.cos(a))) * 0.007
    pts.append((tip.x, tip.y, 0.005, 0.005))
    return pts


def unterflasche():
    u = Part("Unterflasche")
    ys = SHEAVE_Y
    # Haken mit Maulsicherung
    hp = hook_path()
    u.sweep([(0.0, y, z) for z, y, _, _ in hp], [(ra, rb) for _, _, ra, rb in hp], (1, 0, 0), "Haken", 14)
    u.beam((0, 0.146, 0.014), (0, 0.112, 0.036), 0.004, 0.016, "Blank")
    u.cyl(0.006, 0.05, (0, 0.148, 0.012), "x", "Blank", 8)
    u.lathe([(0.166, 0.019), (0.166, 0.03), (0.186, 0.03), (0.186, 0.019)], (0, 0, 0), "y", "Stahl", 6)
    # Traverse mit Zapfen in den Seitenschilden
    u.box((0.07, 0.05, 0.07), (0, 0.21, 0), "Stahl")
    u.cyl(0.02, 0.1, (0, 0.21, 0), "z", "Stahl", 14)
    # Seilrolle auf ihrer Achse
    u.lathe([(-0.027, 0.02), (-0.027, 0.035), (-0.012, 0.045), (-0.012, 0.085), (-0.016, 0.092), (-0.016, 0.103), (-0.011, 0.103),
             (-0.003, 0.0895), (0.003, 0.0895), (0.011, 0.103), (0.016, 0.103), (0.016, 0.092), (0.012, 0.085), (0.012, 0.045),
             (0.027, 0.035), (0.027, 0.02)], (0, ys, 0), "z", "Stahl", 28)
    u.cyl(0.018, 0.1, (0, ys, 0), "z", "Stahl", 14)
    # Seitenschilde mit gelb-schwarzen Warnstreifen
    outline = [(-0.05, 0.172), (0.05, 0.172)]
    for deg in range(-25, 206, 10):
        a = math.radians(deg)
        outline.append((0.117 * math.cos(a), ys + 0.117 * math.sin(a)))
    yellow, black = u.mi("Gelb"), u.mi("Schwarz")
    stripe = Vector((1, 1, 0)).normalized()
    width = 0.03
    for s in (-1, 1):
        tmp = bmesh.new()
        lo = [tmp.verts.new((x, y, s * 0.037)) for x, y in outline]
        hi = [tmp.verts.new((x, y, s * 0.045)) for x, y in outline]
        n = len(outline)
        for i in range(n):
            tmp.faces.new((lo[i], lo[(i + 1) % n], hi[(i + 1) % n], hi[i]))
        tmp.faces.new(lo)
        tmp.faces.new(list(reversed(hi)))
        for k in range(-2, 22):
            bmesh.ops.bisect_plane(tmp, geom=tmp.verts[:] + tmp.edges[:] + tmp.faces[:], dist=1e-6,
                                   plane_co=stripe * (k * width), plane_no=stripe)
        for f in tmp.faces:
            f.material_index = black if int(math.floor(f.calc_center_median().dot(stripe) / width)) % 2 else yellow
        u.merge(tmp)
        zo = s * 0.045
        u.cyl(0.032, 0.008, (0, ys, zo + s * 0.004), "z", "Blank", 18)              # Achshalter
        u.hexbolt((0, ys, zo + s * 0.011), "z", "Zink", 0.012, 0.008)
        u.box((0.06, 0.02, 0.006), (0, 0.21, zo + s * 0.003), "Blank")               # Zapfensicherung
        for bx in (-0.02, 0.02):
            u.hexbolt((bx, 0.21, zo + s * 0.009), "z", "Zink", 0.006, 0.005)
        for bx, by in ((0.0, ys + 0.109), (-0.078, 0.258), (0.078, 0.258)):
            u.hexbolt((bx, by, zo + s * 0.004), "z", "Zink", 0.011, 0.008)
    for bx, by in ((0.0, ys + 0.109), (-0.078, 0.258), (0.078, 0.258)):               # Distanzbolzen
        u.cyl(0.006, 0.076, (bx, by, 0), "z", "Zink", 8)
    # Seilschutz über der Rolle
    band = []
    for deg in range(52, 129, 8):
        a = math.radians(deg)
        band.append((0.1165 * math.cos(a), ys + 0.1165 * math.sin(a)))
    for deg in range(128, 51, -8):
        a = math.radians(deg)
        band.append((0.111 * math.cos(a), ys + 0.111 * math.sin(a)))
    u.prism(band, (0, 0, 0), (1, 0, 0), (0, 1, 0), -0.0375, 0.0375, "Gelb")
    u.marker("Seil_A", (ROPE_X, ys, 0))
    u.marker("Seil_B", (-ROPE_X, ys, 0))
    ob = u.build()

    # Kettengehänge: Aufhängeglied im Hakenmaul. Die Stränge zu den Kranösen legt das Spiel aus einzelnen
    # Kettengliedern (lange Achse y, Teilung = Abstand zweier Glieder).
    g = Part("Gehaenge")
    g.link((0, -0.013, 0), (0, 1, 0), (0, 0, 1), 0.033, 0.064, 0.007, "Rot", 8, 7)
    g.marker("Kette_Start", (0, -0.071, 0))
    g.build()
    k = Part("Kettenglied")
    k.link((0, 0, 0), (0, 1, 0), (0, 0, 1), 0.010, 0.016, 0.005, "Kette")
    k.marker("Kette_Teilung", (0, 0.026, 0))
    k.build()
    return ob


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = args[0] if args else "models/hallenkran.glb"
    bpy.ops.wm.read_factory_settings(use_empty=True)
    kranbahn()
    bruecke()
    katze()
    wagen = Part("Kabelwagen")
    carrier(wagen, (0, 0, 0))
    wagen.build()
    unterflasche()
    bpy.ops.export_scene.gltf(filepath=bpy.path.abspath(out), export_format="GLB", export_yup=True,
                              export_apply=False, export_animations=False, export_cameras=False, export_lights=False)
    print("geschrieben:", out)


main()
