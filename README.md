# Weight Painter Plugin for Godot

This is a Weight painter attempt for Godot 4.5+

You can paint weights. By using the UI you can specify the intensity and size of your brush. Three modes are available: brush tool, smooth tool and eraser.

But no it's not working well

# How to use

- Clone the repo into your addons/ folder: `cd addons && git clone https://github.com/cabra-lat/cabra.lat_uv_painter.git`
- Enable the addon in `Project/Project Settings/Plugins`
- Select a `MeshInstance` node in your scene tree, a brush button will appear in the 3D view top menu
- Click on the brush button
- Start painting !

Yes I used the [StrayEddy/GodotPlugin-MeshPainter](https://github.com/StrayEddy/GodotPlugin-MeshPainter) as a base to bootstrap the painting but it's crashing a lot in my current setup with 2011 intel integrated graphics.
