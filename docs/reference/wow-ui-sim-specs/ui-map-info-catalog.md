# UiMap information catalog

For Retail, `C_Map.GetMapInfo` uses the seeded map state first. For an
unseeded ID, it uses the generated UiMap catalog before the existing generic
map record. Other profiles retain their existing behavior; their map catalogs
and hierarchies are not established by the Retail export.

The catalog contains named rows from an enUS UiMap export. The contributor
reported build 12.1.0.69497. Independently, all 1,958 generated rows and their
names, types, parent IDs, and flags match a local 12.1.0.69933 export. This
comparison does not establish the claimed earlier build's provenance.

Seeded map 946 is Cosmic, type 0, with parent 0. Seeded map 947 is Azeroth,
type 1, with parent 946. Seeded values take precedence over the catalog; this
contract does not claim that every seeded hierarchy or flag matches the client.
