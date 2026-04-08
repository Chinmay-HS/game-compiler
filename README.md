## game-compiler

# To run follow the following commands
`chmod +x gcl_starter.sh`
`./gcl_starter.sh`

Stage 1 — Lexer. The script feeds a real GSL game script (Player and Enemy entities with physics blocks, event handlers, imports) into a hand-written tokeniser. You'll see every token printed with its type — kw:entity, Identifier "Player", kw:physics, Number "5.0", etc. This is literally the first thing any compiler does.
Stage 2 — Parser → AST. Those tokens get fed into a recursive descent parser that builds a tree. The output is the AST printed in parenthesised form, like (Entity "Player" (LetDecl "speed" ...) (PhysicsBlock ...) (Handler "onUpdate" ...)). This is the data structure that every subsequent compiler stage operates on.
Stage 3 — Physics Simulation. Three spheres (BallA/B/C) with different masses and restitution values drop under gravity, bounce off the floor, and collide with each other. You'll see a table of positions and velocities printed every 0.5 seconds across a 3-second simulation. The maths is real: semi-implicit Euler integration, impulse-based collision resolution with mass ratios.
Stage 4 — Shader Compilation. Two real GLSL shaders (a Blinn-Phong vertex + fragment pair with UBO bindings and a texture sampler) are written to disk and validated by glslangValidator. Then a deliberately broken shader is run through the same pipeline so you can see what compiler errors look like. This is the exact same tool the Vulkan SDK uses.