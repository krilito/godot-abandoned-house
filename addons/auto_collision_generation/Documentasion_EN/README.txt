=====================================
 AUTO COLLISION GENERATOR (Free 1.0)
=====================================

Author: RaykitsID

This plugin automatically generates collision shapes for 3D 
meshes in Godot Engine. It's designed to be mobile-friendly, 
so you don't need to use right-click editor menus that are 
hard to reach on a phone screen.


INSTALLATION & ACTIVATION
----------------------------
1. Copy the plugin folder into your project's "addons" folder.

2. Go to Project > Project Settings > Globals tab.
   Click "Select Script/Scene", choose the collision_map.gd 
   file from the plugin folder, then check the "Enable" box.

3. Once enabled, a new "Auto Collision" tab will appear at 
   the bottom of the Godot editor.

4. IMPORTANT - if your model is an instanced GLB/GLTF/FBX scene:
   Long-press the model node in the Scene panel, then enable 
   "Editable Children".
   Without this, the generated collisions may disappear when 
   you close and reopen the scene.

5. Open the scene you want to process, tap the "Auto Collision" 
   tab, then press the "Generate Collision" button.

6. Check the result in the Scene panel: a new StaticBody3D and 
   CollisionShape3D node will appear under each mesh.

A step-by-step visual guide is available in the 
"Documentation" folder.


USAGE NOTES
-------------
- This plugin works on any node of type MeshInstance3D.
- Best suited for static maps/levels (walls, floors, props),
  not for moving characters or objects.
- If a node has no mesh, it will simply be skipped (this is 
  not an error).
- Always back up your project before using any plugin,
  including this one.

For license information and liability terms, see License.txt.
