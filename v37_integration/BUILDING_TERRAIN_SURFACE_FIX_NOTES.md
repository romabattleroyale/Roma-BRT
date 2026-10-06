# Building terrain surface fix

Runtime alignment now needs to verify the actual mesh bottom against Terrain3D, not only the building pivot. The intended fix is a small safety clearance above the sampled Terrain3D surface, while leaving terrain, river and persisted placements untouched.
