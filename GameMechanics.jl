using LinearAlgebra

struct ObjectGraphics
	EB::ElementBuffer
	VA::VertexArray
	shader::Shader
end

struct Block
	position::Vector{Float32}
	width::Float32
	height::Float32
	graphics::ObjectGraphics
end

mutable struct PlayerBar
	position::Vector{Float32}
	velocity::Vector{Float32}
	width::Float32
	height::Float32
	graphics::ObjectGraphics
end

mutable struct PlayerCircle
	position::Vector{Float32}
	velocity::Vector{Float32}
	radius::Float32
	graphics::ObjectGraphics
end

const BarWidth, BarHeight, BarVelocity = 0.3, 0.04, 0.02;
const CircleRadius = 0.02;
const nLines, nBlocks = 9, 8;
const BlockWidth, BlockHeight = 0.15, 0.05;

function InitializeGraphics(Vertices::Vector{Point{2, Float32}}, Elements::Vector{Vec3{UInt32}}, VertexShader::String, FragmentShader::String)
	shader = Shader(CreateShader(VertexShader, FragmentShader))
	pos_attribute = glGetAttribLocation(shader.ID, "position")

	VB = VertexBuffer(Ref(GLuint(0)), length(Vertices[1]), sizeof(Vertices))
	GenerateBuffer(GL_ARRAY_BUFFER, VB, Vertices)

	EB = ElementBuffer(Ref(GLuint(0)), length(Elements))
	GenerateBuffer(GL_ELEMENT_ARRAY_BUFFER, EB, Elements)

	VA = VertexArray(Ref(GLuint(0)))
	GenerateVertexArray(VA)
	SetVertexArray(pos_attribute, length(Vertices[1]), GL_FLOAT, GL_FALSE, 0, C_NULL)

	return ObjectGraphics(EB,VA,shader)
end

function CollisionDetection!(c::PlayerCircle) #Detect a collision of the circle with the boundaries
	collisioned = false
	defeat = false
	if c.position[1] > 1-c.radius && c.velocity[1] > 0.0 || c.position[1] < -(1-c.radius) && c.velocity[1] < 0.0 #Collision on the left/right
		c.velocity[1] = -c.velocity[1]
		collisioned = true
	end
	if c.position[2] > 1-c.radius && c.velocity[2] > 0.0 #Collision on the top
		c.velocity[2] = -c.velocity[2]
		collisioned = true
	elseif c.position[2] < -(1-c.radius) && c.velocity[2] < 0.0 #Collision on the bottom
		defeat = true
	end
	return collisioned, defeat
end

function CollisionDetection!(c::PlayerCircle,b::PlayerBar)::Bool #Detect a collision of the circle with the playerBar
	collisioned = false
	if abs(c.position[2]-b.position[2]) < c.radius + b.height/2 #Broad detection
		if abs(c.position[1]-b.position[1]) < c.radius + b.width/2
			collisioned = true
			c.velocity[1] = c.velocity[1]+(c.position[1]-b.position[1])*0.03
			if c.velocity[2] < 0.0
				c.velocity[2] = -c.velocity[2]
			end
		end
	end
	return collisioned
end

function CollisionDetection!(c::PlayerCircle,b::Vector{Block})::Bool #Detect a collision of the circle with a block
	collisioned = false
	for i in 1:length(b)
		if abs(c.position[2]-b[i].position[2]) < c.radius + b[i].height/2
			if abs(c.position[1]-b[i].position[1]) < c.radius + b[i].width/2
				collisioned = true
				if c.position[2] > b[i].position[2]-b[i].height/2 && c.position[2] < b[i].position[2]+b[i].height/2
					c.velocity[1] = -c.velocity[1]
				else
					c.velocity[2] = -c.velocity[2]
				end
				deleteat!(b,i)
				break
			end
		end
	end

	return collisioned
end

function UpdatePhysics!(window::GLFW.Window, playerBar::PlayerBar, playerCircle::PlayerCircle, Blocks::Vector{Block})::Bool
	GLFW.PollEvents()
	if GLFW.GetKey(window, GLFW.KEY_LEFT) == true
		if playerBar.position[1] >= -1.0 + BarWidth/2 + playerBar.velocity[1]
			playerBar.position[1] -= playerBar.velocity[1]
		end
	elseif GLFW.GetKey(window, GLFW.KEY_RIGHT) == true
		if playerBar.position[1] <= 1.0 - BarWidth/2 - playerBar.velocity[1]
			playerBar.position[1] += playerBar.velocity[1]
		end
	end

	collisioned, defeat = CollisionDetection!(playerCircle)
	if !collisioned
		collisioned = CollisionDetection!(playerCircle,playerBar)
	end
	if !collisioned
		collisioned = CollisionDetection!(playerCircle,Blocks)
	end

	playerCircle.position .+= playerCircle.velocity
	return defeat
end

function UpdateDraw(Object, color::Vector{Float32})
	SetUniform(Object.graphics.shader.ID, "translation", Object.position[1], Object.position[2])
	SetUniform(Object.graphics.shader.ID, "triangleColor", color[1], color[2], color[3], color[4])
	Draw(Object.graphics.EB, Object.graphics.VA)
end

function launch(windowWidth::Int64, windowHeight::Int64)::Nothing

	# Graphics data
	BarVertices, BarElements = RectangleData(BarWidth, BarHeight, windowWidth, windowHeight)
	CircleVertices, CircleElements = CircleData(CircleRadius, 64, windowWidth, windowHeight)
	BlockVertices, BlockElements = RectangleData(BlockWidth, BlockHeight, windowWidth, windowHeight)

	# Create the window.
	window = GLFW.CreateWindow(windowWidth,windowHeight,"Breakout",#=GLFW.GetPrimaryMonitor()=#)
	GLFW.MakeContextCurrent(window)

	GLFW.SetInputMode(window, GLFW.STICKY_KEYS, true)

	playerBar = PlayerBar([0,-0.7],[0.02,0],BarWidth, BarHeight,InitializeGraphics(BarVertices,BarElements,vertex_shader,fragment_shader))
	playerCircle = PlayerCircle([0,-0.7+(BarHeight/2+CircleRadius)],[0,0],CircleRadius,InitializeGraphics(CircleVertices,CircleElements,vertex_shader,fragment_shader))
	Blocks = Vector{Block}(undef,nLines*nBlocks)
	for i in 1:nLines
		for j in 1:nBlocks
			Blocks[(i-1)*nBlocks+j] = Block([(i-floor(nBlocks/2)-1)*BlockWidth*1.1, (j-1)*BlockHeight*1.1+0.3],BlockWidth,BlockHeight,InitializeGraphics(BlockVertices,BlockElements,vertex_shader,fragment_shader))
		end
	end

	glClearColor(0,0,0,0)

	start = false
	# Draw while waiting for a close event
	while !GLFW.WindowShouldClose(window)
		glClear(GL_COLOR_BUFFER_BIT)

		# Wait until the player press space
		while !start
			UpdateDraw(playerCircle, [1f0, 1f0, 1f0, 1.0f0])
			UpdateDraw(playerBar, [1f0, 1f0, 1f0, 1.0f0])
			for i in 1:length(Blocks)
				UpdateDraw(Blocks[i],[0f0, 0.5f0, 1f0, 1f0])
			end

		    GLFW.SwapBuffers(window)
			GLFW.PollEvents()
			if GLFW.GetKey(window, GLFW.KEY_SPACE) == true
				start = true
				playerCircle.velocity = [0.0,0.02]
			end
			if GLFW.WindowShouldClose(window)
				break
			end
		end

		# Pong
		UpdateDraw(playerCircle, [1f0, 1f0, 1f0, 1.0f0])
		UpdateDraw(playerBar, [1f0, 1f0, 1f0, 1.0f0])
		for i in 1:length(Blocks)
			UpdateDraw(Blocks[i],[0f0, 0.5f0, 1f0, 1f0])
		end

	    GLFW.SwapBuffers(window)
		defeat = UpdatePhysics!(window,playerBar,playerCircle,Blocks)
		if defeat
			GLFW.SetWindowShouldClose(window, true)
		end
	end
	GLFW.DestroyWindow(window)

	return nothing
end