import SwiftUI

/// The Moon as a sphere, lit the way it is lit tonight.
///
/// Weather draws a photograph of the Moon and slides a shadow across it. There
/// is no photograph in this bundle, so the near side is painted instead — the
/// maria roughly where they are, a handful of craters, a radial highlight for
/// volume — and the same shadow geometry runs over the top of it.
struct MoonDisc: View {

    /// Sun–Moon elongation in degrees: 0 new, 90 first quarter, 180 full,
    /// 270 third quarter. Everything about the drawing follows from it.
    let angle: Double

    var size: CGFloat = 112

    var body: some View {
        ZStack {
            surface

            // The unlit part. Not opaque: the real Moon's dark limb still
            // reads as a sphere, and so does this one over the card's glass.
            // The blur is what makes a terminator instead of a cut, and the
            // shape reaches past the disc so only the terminator is softened —
            // the limb stays where the clip puts it.
            MoonShadowShape(angle: angle)
                .fill(Color(hex: 0x141419).opacity(0.88), style: FillStyle(eoFill: true))
                .blur(radius: size * 0.013)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .animation(.easeInOut(duration: 0.5), value: angle)
        .accessibilityHidden(true)
    }

    private var surface: some View {
        Canvas { context, canvas in
            let width = canvas.width
            let height = canvas.height

            func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
                CGRect(
                    x: (x - w / 2) * width,
                    y: (y - h / 2) * height,
                    width: w * width,
                    height: h * height
                )
            }

            // Rock. Filled edge to edge rather than as a circle: the blur
            // below would fade a circle's rim, and the clip draws the limb.
            context.fill(
                Path(CGRect(origin: .zero, size: canvas)),
                with: .radialGradient(
                    Gradient(colors: [
                        Color(hex: 0xFBF9F4),
                        Color(hex: 0xDEDAD1),
                        Color(hex: 0xA29E94),
                    ]),
                    center: CGPoint(x: width * 0.42, y: height * 0.38),
                    startRadius: 0,
                    endRadius: width * 0.82
                )
            )

            // The seas, traced rather than assembled out of circles. Circles
            // gave the disc a row of round spots; the near side's actual mare
            // edges are ragged, and the bright highland running between
            // Imbrium and Serenitatis is as much of the face as the dark is.
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: width * 0.006))

                var seas = Path()
                for outline in Self.maria {
                    seas.addPath(Self.blob(outline, width: width, height: height))
                }
                seas.addEllipse(in: rect(0.815, 0.28, 0.125, 0.095))  // Crisium
                layer.fill(seas, with: .color(Color(hex: 0x33323C).opacity(0.30)))

                // A second pass over the darkest basins, for the tonal range a
                // single flat fill cannot carry.
                var deep = Path()
                for sea in Self.deepMaria {
                    deep.addEllipse(in: rect(sea.x, sea.y, sea.width, sea.height))
                }
                layer.fill(deep, with: .color(Color(hex: 0x33323C).opacity(0.15)))
            }

            // Fine cratering. Too small to name, and the reason the highlands
            // read as rock rather than as paper.
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: width * 0.003))

                for speck in Self.speckles {
                    let bowl = rect(speck.x, speck.y, speck.radius * 2, speck.radius * 2)
                    layer.fill(Path(ellipseIn: bowl), with: .color(.white.opacity(0.22)))
                    layer.fill(
                        Path(ellipseIn: bowl.offsetBy(dx: bowl.width * 0.22, dy: bowl.height * 0.22)
                            .insetBy(dx: bowl.width * 0.20, dy: bowl.height * 0.20)),
                        with: .color(Color(hex: 0x33323C).opacity(0.20))
                    )
                }
            }

            context.drawLayer { layer in
                layer.addFilter(.blur(radius: width * 0.004))

                // Tycho's rays — the one feature of the near side that names it
                // at a glance, as a bright wash rather than drawn spokes.
                let rays = CGPoint(x: width * 0.45, y: height * 0.79)
                layer.fill(
                    Path(ellipseIn: CGRect(
                        x: rays.x - width * 0.28,
                        y: rays.y - height * 0.28,
                        width: width * 0.56,
                        height: height * 0.56
                    )),
                    with: .radialGradient(
                        Gradient(colors: [.white.opacity(0.20), .white.opacity(0.07), .white.opacity(0)]),
                        center: rays,
                        startRadius: 0,
                        endRadius: width * 0.28
                    )
                )

                // Craters are texture at this size, not features: a bright rim
                // with the floor shaded away from the Sun, both faint enough
                // that they never compete with the seas.
                for crater in Self.craters {
                    let bowl = rect(crater.x, crater.y, crater.radius * 2, crater.radius * 2)

                    layer.fill(Path(ellipseIn: bowl), with: .color(.white.opacity(0.26)))
                    layer.fill(
                        Path(ellipseIn: bowl.offsetBy(dx: bowl.width * 0.20, dy: bowl.height * 0.20)
                            .insetBy(dx: bowl.width * 0.18, dy: bowl.height * 0.18)),
                        with: .color(Color(hex: 0x35343E).opacity(0.22))
                    )
                }
            }
        }
        .overlay {
            // Limb darkening — the edge of a sphere turns away from the light.
            RadialGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Color(hex: 0x2A2A33).opacity(0.10), location: 0.62),
                    .init(color: Color(hex: 0x2A2A33).opacity(0.58), location: 1),
                ],
                center: UnitPoint(x: 0.42, y: 0.38),
                startRadius: size * 0.06,
                endRadius: size * 0.60
            )
        }
    }

    // MARK: - The near side

    private struct Sea {
        let x, y, width, height: Double
    }

    private struct Crater {
        let x, y, radius: Double
    }

    /// The dark seas as outlines, in unit coordinates of the disc: each entry
    /// is a ring of points that `blob` rounds off into a closed curve. Placed
    /// by eye from the near side as it is seen from Earth rather than surveyed,
    /// but kept separate the way they really are — the bright highland between
    /// the two "eyes" is what makes the face read as the Moon's.
    private static let maria: [[(Double, Double)]] = [
        // Mare Imbrium running south into Oceanus Procellarum: the whole
        // western half of the near side, one connected plain.
        [
            (0.33, 0.15), (0.44, 0.17), (0.50, 0.25), (0.47, 0.34), (0.40, 0.38),
            (0.37, 0.47), (0.36, 0.56), (0.32, 0.64), (0.26, 0.66), (0.21, 0.60),
            (0.18, 0.50), (0.18, 0.40), (0.21, 0.30), (0.26, 0.21),
        ],

        // Mare Frigoris — the thin arc along the northern limb.
        [
            (0.37, 0.13), (0.50, 0.11), (0.62, 0.15), (0.63, 0.19),
            (0.50, 0.16), (0.38, 0.17),
        ],

        // Serenitatis into Tranquillitatis and down to Nectaris: the eastern
        // chain, and the darkest ground on the disc.
        [
            (0.55, 0.23), (0.64, 0.22), (0.70, 0.29), (0.69, 0.36), (0.74, 0.41),
            (0.77, 0.48), (0.73, 0.55), (0.69, 0.59), (0.66, 0.66), (0.61, 0.63),
            (0.60, 0.55), (0.57, 0.47), (0.55, 0.38), (0.52, 0.29),
        ],

        // Mare Fecunditatis, east and slightly south of it.
        [
            (0.78, 0.48), (0.83, 0.53), (0.82, 0.60), (0.77, 0.63),
            (0.73, 0.58), (0.74, 0.51),
        ],

        // Mare Nubium — the mouth of the face.
        [
            (0.40, 0.57), (0.50, 0.59), (0.54, 0.65), (0.48, 0.71),
            (0.39, 0.71), (0.33, 0.67), (0.34, 0.60),
        ],

        // Mare Humorum, the small round one southwest of it.
        [
            (0.27, 0.60), (0.32, 0.62), (0.32, 0.68), (0.27, 0.70), (0.24, 0.65),
        ],
    ]

    /// Darkened a second time: the basins that stand out even to the eye.
    private static let deepMaria: [Sea] = [
        Sea(x: 0.815, y: 0.28, width: 0.11, height: 0.08),  // Crisium
        Sea(x: 0.61, y: 0.30, width: 0.15, height: 0.14),   // Serenitatis
        Sea(x: 0.67, y: 0.47, width: 0.18, height: 0.16),   // Tranquillitatis
        Sea(x: 0.40, y: 0.26, width: 0.19, height: 0.17),   // Imbrium
    ]

    /// A ring of points rounded into a closed curve: each segment is a quad
    /// curve from midpoint to midpoint with the corner as its control, so the
    /// outline passes smoothly through the polygon rather than along it.
    private static func blob(_ points: [(Double, Double)], width: Double, height: Double) -> Path {
        let ring = points.map { CGPoint(x: $0.0 * width, y: $0.1 * height) }
        guard ring.count > 2 else { return Path() }

        func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }

        var path = Path()
        path.move(to: midpoint(ring[ring.count - 1], ring[0]))
        for index in ring.indices {
            let corner = ring[index]
            let next = ring[(index + 1) % ring.count]
            path.addQuadCurve(to: midpoint(corner, next), control: corner)
        }
        path.closeSubpath()
        return path
    }

    private static let craters: [Crater] = [
        Crater(x: 0.45, y: 0.79, radius: 0.028),  // Tycho
        Crater(x: 0.41, y: 0.44, radius: 0.024),  // Copernicus
        Crater(x: 0.30, y: 0.44, radius: 0.016),  // Kepler
        Crater(x: 0.24, y: 0.37, radius: 0.013),  // Aristarchus
        Crater(x: 0.53, y: 0.71, radius: 0.022),  // Clavius
        Crater(x: 0.63, y: 0.77, radius: 0.015),
        Crater(x: 0.56, y: 0.20, radius: 0.014),  // Plato
        Crater(x: 0.72, y: 0.66, radius: 0.013),
        Crater(x: 0.49, y: 0.56, radius: 0.012),  // Ptolemaeus
    ]

    /// Craters too small to name, scattered over the disc. Generated once from
    /// a fixed seed so the face is the same face every time it is drawn.
    private static let speckles: [Crater] = {
        var seed: UInt64 = 0x5EED_B163
        func next() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double((seed >> 33) % 10_000) / 10_000
        }

        var specks: [Crater] = []
        while specks.count < 54 {
            let x = next()
            let y = next()
            let size = next()
            // Inside the disc, and off the limb where a crater would be edge on.
            let dx = x - 0.5
            let dy = y - 0.5
            guard dx * dx + dy * dy < 0.19 else { continue }
            specks.append(Crater(x: x, y: y, radius: 0.004 + size * 0.009))
        }
        return specks
    }()
}

/// The lit face: half the disc on the sunward limb, closed by the terminator.
///
/// The terminator is a semicircle on the sphere, so it projects to a half
/// ellipse whose width is `cos(elongation)` of the radius — signed, which is
/// what turns a crescent into a gibbous as the angle passes a quarter.
struct MoonLitShape: Shape {

    let angle: Double

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let theta = angle * .pi / 180
        let bulge = cos(theta)
        // Waxing lights the right limb, waning the left.
        let limb: CGFloat = angle.truncatingRemainder(dividingBy: 360) < 180 ? 1 : -1

        var path = Path()
        let steps = 96

        // Down the lit limb, top to bottom.
        for step in 0...steps {
            let u = Double(step) / Double(steps) * .pi
            let point = CGPoint(
                x: center.x + limb * radius * CGFloat(sin(u)),
                y: center.y - radius * CGFloat(cos(u))
            )
            step == 0 ? path.move(to: point) : path.addLine(to: point)
        }

        // Back up the terminator.
        for step in stride(from: steps, through: 0, by: -1) {
            let u = Double(step) / Double(steps) * .pi
            path.addLine(to: CGPoint(
                x: center.x + limb * radius * CGFloat(bulge * sin(u)),
                y: center.y - radius * CGFloat(cos(u))
            ))
        }

        path.closeSubpath()
        return path
    }
}

/// The disc and the lit face in one path, to be filled even-odd: what is
/// inside both cancels, leaving exactly the part in shadow.
struct MoonShadowShape: Shape {

    let angle: Double

    func path(in rect: CGRect) -> Path {
        // Wider than the disc so the blur that softens the terminator has
        // nothing to fade at the limb, where the clip already draws the edge.
        let side = min(rect.width, rect.height) * 1.2
        let disc = CGRect(
            x: rect.midX - side / 2,
            y: rect.midY - side / 2,
            width: side,
            height: side
        )

        var path = Path(ellipseIn: disc)
        path.addPath(MoonLitShape(angle: angle).path(in: rect))
        return path
    }
}

#if DEBUG
#Preview("Phases") {
    let angles: [Double] = [0, 45, 90, 135, 180, 225, 270, 315]

    return ZStack {
        Color(hex: 0x1B2434).ignoresSafeArea()

        VStack(spacing: 22) {
            ForEach([Array(angles.prefix(4)), Array(angles.suffix(4))], id: \.self) { row in
                HStack(spacing: 22) {
                    ForEach(row, id: \.self) { angle in
                        VStack(spacing: 6) {
                            MoonDisc(angle: angle, size: 70)
                            Text("\(Int(angle))°")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }
            }
        }
    }
}
#endif
