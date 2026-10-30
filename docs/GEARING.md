# Gearing and resistance

## Even effort

The default 24-gear table is calibrated at 90 rpm on a flat reference road. Gear 12 is 150 W and neighboring gears differ by 9 W: gear 1 is 51 W and gear 24 is 258 W. The model solves the road-load equation backward to find the virtual ratio for each reference effort. Actual effort changes with cadence, grade, wind, and the road parameters supplied by Zwift.

Each rider can save their own cruising effort (75–400 W) and spacing (3–8% of cruising effort). A linear effort table avoids the large upper-gear jumps that occur with a simple geometric ratio progression.

## Match a bike

Enter one or two chainrings (20–80 teeth) and 1–24 different rear sprockets (5–100 teeth). Enter every sprocket for an exact match. The approximate cassette generator uses the selected endpoints and count; it cannot identify a manufacturer’s actual cassette from a range alone.

All chainring/sprocket combinations are sorted by ratio. A 2×12 drivetrain provides 24 combinations, including overlapping ratios and cross-chain combinations. Sequential shifting follows this sorted table rather than a mechanical shift path or synchronized-shifting algorithm.

The SRAM 48/35 and 10–36 preset uses sprockets **10, 11, 12, 13, 15, 17, 19, 21, 24, 28, 32, 36**. Its range is 35/36 to 48/10.

Tooth counts describe the virtual bike. They do not have to match the physical chainring and Cog driving the trainer. The physical ratio still affects flywheel speed, inertia, and the trainer’s attainable minimum resistance.

## Ratio, speed, and power

At a 2,105 mm wheel circumference, 48×10 at 100 rpm corresponds to 60.624 km/h of virtual wheel speed. There is no single wattage associated with that gear: road load depends on gradient, wind, mass, rolling resistance, and aerodynamic drag. Zwift calculates displayed road speed separately from measured rider power and its world model.

At flat/no-wind reference conditions, a 75 kg rider plus a 9 kg bike, Crr 0.004, and CdA 0.51 m², the model requires about 1,547 W for that example. The command is capped at 1,000 W. A smaller CdA of 0.32 m² would give about 992 W; these are calculated examples, not measurements of an outdoor rider’s effort.

**Load scale** (25–100%) reduces the modeled effort in Match a bike mode while preserving ratio order and virtual wheel speed. It does not scale measured power sent to Zwift or change ERG workout targets. At 25%, the first example becomes approximately 387 W. This is assisted effort rather than full modeled road load.

## Trainer commands

The model converts cadence and virtual gearing into target power and sends ordinary FTMS power commands to the physical KICKR. Measured power, cadence, and speed are forwarded to Zwift without inventing or scaling rider power.

Free-ride transitions use a 0.55-second smoothing constant, with increases limited to 60 W/s and decreases to 90 W/s. Commands are capped at 1,000 W. Coasting below 20 rpm releases load; zero-load requests bypass smoothing. ERG targets are forwarded from Zwift and shifting is paused.

This is an approximation, not a full inertial simulation. Cadence estimation, trainer response, minimum resistance, and capped high gears can affect feel.
