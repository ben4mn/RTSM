# Room to build and expand

The owner found the maps cramped and short of usable resource deposits. Generator 3 changes the terrain contract: larger home clearings, nearby finite groves, and stocked side compounds connected by broad routes.

## Geometry and travel

The battlefield grows from 72x72 to 88x88 tiles, while Town Center anchors move from an edge padding of 6 to 14. Opposing bases retain their previous 59-tile separation on each axis. Extra land creates space behind and beside towns rather than lengthening the initial trip to the opponent. The grid has 7,744 cells instead of 5,184, an increase of 49.4%; this is a real map-generation/pathfinding cost, not a performance improvement claim.

Each home receives a 23x23 terrain clearing instead of 13x13. Resource patches occupy distinct sides and remain within the existing circular Town Center reveal. The center and two flank routes are carved nine tiles wide. Two expansion compounds per side each have a 17x17 cleared perimeter, a resource-free 5x5 central construction pad, and a broad connection back toward home. These are terrain clearings: normal ownership, vision, clearance, cost and building-placement rules still apply.

Open Plains retains scattered terrain and open approaches. River Crossings retains its separating river and three independent crossings. Woodland Flanks retains deeper woodland masses around open routes. Authored crossing and woodland anchors scale with field dimensions. Every terrain edit and resource patch is reflected across the diagonal that maps one starting base onto the other.

## Finite resource stock

Per-node quantities remain unchanged: a berry tile holds 200 food, a tree tile 250 wood, and a gold tile 400 gold. No resources are added to player banks.

| Guaranteed deposit | Previous nodes | Generator 3 nodes | Previous stock | Generator 3 stock |
| --- | ---: | ---: | ---: | ---: |
| Home berries | 4 | 8 | 800 food | 1,600 food |
| Home trees | 8 | 24 | 2,000 wood | 6,000 wood |
| Home gold | 2 | 4 | 800 gold | 1,600 gold |
| Each side expansion: berries | 2 | 8 | 400 food | 1,600 food |
| Each side expansion: trees | 4 | 20 | 1,000 wood | 5,000 wood |
| Each side expansion: gold | 1 | 4 | 400 gold | 1,600 gold |

Finite groves supplement farms, camps and scouting. Extra deposits elsewhere still vary by seed. Terrain carving finishes before guaranteed stock is placed. All carved route cells are reserved against subsequent resource placement; expansion patches fit around those routes.

## Compatibility and validation

MapData.GENERATOR_VERSION is 3. Older clients regenerate a different battlefield from the same seed, so deployment requires the corresponding network compatibility change; a cosmetic version increment alone is insufficient. Root integration owns the protocol update and matching client/server publication.

Validation completed successfully:

- 25,721 assertions across nine actual before/after maps: seeds 101, 202 and 424242 for each archetype.
- 105 generated archetype cases, covering all sixteen randomized crossing configurations, with source determinism, mirrored terrain, complete guaranteed expansion stock and independently usable river crossings.
- 64 opening-fairness cases using actual gather/dropoff paths around solid starting Town Centers.
- Every reserved route cell remained grass after resource placement.

The nine measured maps all had fully connected walkable land. Across the broader 105-map check the minimum was 99.972%, with all home resources, expansion compounds and tactical routes reachable. Candidate opening deposit travel was equal between reflected sides in the nine-map comparison.

Terrain-only 4x4 home building anchors increased from **51 to 235** on every measured map, excluding the initial Town Center footprint. These counts measure available ground, not current visibility, building spacing or affordability. Base separation stayed at 59 tiles on each axis.

| Whole-map finite stock, seed 101 | Food before -> after | Wood before -> after | Gold before -> after |
| --- | ---: | ---: | ---: |
| Open Plains | 6,000 -> 12,800 | 27,000 -> 54,000 | 8,800 -> 15,200 |
| River Crossings | 6,400 -> 12,400 | 17,500 -> 51,000 | 8,800 -> 13,600 |
| Woodland Flanks | 6,200 -> 12,400 | 92,000 -> 237,000 | 8,800 -> 15,200 |

Local generator time had a median of **32.0 ms before and 65.2 ms after**, with a candidate maximum of 87.2 ms. This includes extra route and resource placement work. It is a local diagnostic, not physical-phone FPS, heat or battery evidence; the larger tile grid and added resource nodes still need a real-device performance check.

The size-aware topology renderer produced a visually inspected three-map sheet from actual generated seed-101 output, including runtime route paths. Detailed source hashes and reports are retained in the current recovery workspace's map-v3-final-validation.json, map-homesteads-attempt3.json, map-archetypes-v3-attempt2.json and map-opening-fairness-v3.log. An earlier failed resource-fringe attempt remains preserved; expanding the compounds to 17x17 provided the intended stock without occupying routes.

No combat or balance simulation was substituted for a playtest. The ordinary-match pacing target and late idle-browser error remain open.
