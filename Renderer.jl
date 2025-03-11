using GLFW
using ModernGL
using GLMakie
using GeometryBasics

## Geometries Data

# Give the vertices of a rectangle centered on the origin
function RectangleData(width::Float64, height::Float64, windowWidth::Int64, windowHeight::Int64)::Tuple{Array{Point{2,Float32},1},Array{Vec{3,UInt32},1}}
	nVertices = 4
	verticesArray = Array{Float32,2}(undef, nVertices, 2) #Array of the vertices positions (x,y)
	elementsVector = Vector{Tuple}(undef, 2) #Triangle's points to form the rectangle

	verticesArray[1,1] = -width/2
	verticesArray[1,2] = windowWidth/windowHeight*height/2
	verticesArray[2,1] = width/2
	verticesArray[2,2] = windowWidth/windowHeight*height/2
	verticesArray[3,1] = width/2
	verticesArray[3,2] = -windowWidth/windowHeight*height/2
	verticesArray[4,1] = -width/2
	verticesArray[4,2] = -windowWidth/windowHeight*height/2
	elementsVector[1] = (0,1,2)
	elementsVector[2] = (2,3,0)
	vertices = Point{size(verticesArray,2),Float32}[verticesArray[i,:] for i = 1:size(verticesArray,1)]
	elements = Vec{3,GLuint}[elementsVector[i] for i in 1:length(elementsVector)]
	return vertices, elements
end

# Give the vertices of an approximated circle centered on the origin
function CircleData(R::Float64, nVertices::Int64, windowWidth::Int64, windowHeight::Int64)::Tuple{Array{Point{2,Float32},1},Array{Vec{3,UInt32},1}}
	if nVertices < 3
		nVertices = 3
	end

	verticesArray = Array{Float32,2}(undef, nVertices+1, 2)
	elementsVector = Vector{Tuple}(undef, nVertices)
	verticesArray[1,1] = 0.0
	verticesArray[1,2] = 0.0
	for i in 1:nVertices
		verticesArray[i+1,1] = R*cos(2*π*(i-1)/nVertices)
		verticesArray[i+1,2] = windowWidth/windowHeight*R*sin(2*π*(i-1)/nVertices)
		if i < nVertices
			elementsVector[i] = (0, i, i+1)
		else
			elementsVector[i] = (0, i, 1)
		end
	end
	vertices = Point{size(verticesArray,2),Float32}[verticesArray[i,:] for i = 1:size(verticesArray,1)]
	elements = Vec{3,GLuint}[elementsVector[i] for i in 1:length(elementsVector)]
	return vertices , elements
end

## Buffer

struct VertexBuffer
	ID::Base.RefValue{UInt32}
	VertexLength::Int64
	MemorySize::Int64
end

struct ElementBuffer
	ID::Base.RefValue{UInt32}
	NTriangles::Int64
end

function GenerateBuffer(type::UInt32, Buffer::VertexBuffer, data::Vector{Point{2,Float32}})::Nothing
    glGenBuffers(1, Buffer.ID)
    glBindBuffer(type, Buffer.ID[])
    glBufferData(type, Buffer.MemorySize, data, GL_STATIC_DRAW)
end

function GenerateBuffer(type::UInt32, Buffer::ElementBuffer, data::Array{Vec{3,UInt32},1})::Nothing
    glGenBuffers(1, Buffer.ID)
    glBindBuffer(type, Buffer.ID[])
    glBufferData(type, Buffer.NTriangles * 3 * sizeof(UInt32), data, GL_STATIC_DRAW)
end

function Bind(type::UInt32, BufferID::Base.RefValue{UInt32})::Nothing
    glBindBuffer(type, BufferID[])
end

function UnbindBuffer(type::UInt32)::Nothing
    glBindBuffer(type, 0)
end

function DeleteBuffer(BufferID::Base.RefValue{UInt32})::Nothing
    glDeleteBuffers(1, BufferID[])
end

## Shader

struct Shader
	ID::UInt32
end

# Change the uniform defined in a shader
function SetUniform(ShaderID::UInt32, name::String, v0::Float32, v1::Float32)::Nothing
	UniformLocation = glGetUniformLocation(ShaderID, name)
	glUniform2f(UniformLocation, v0, v1)
end

function SetUniform(ShaderID::UInt32, name::String, v0::Float32, v1::Float32, v2::Float32, v3::Float32)::Nothing
	UniformLocation = glGetUniformLocation(ShaderID, name)
	glUniform4f(UniformLocation, v0, v1, v2, v3)
end

# Connect the shaders by combining them into a program
function CreateShader(vertexSource::String, fragmentSource::String)::UInt32

	vertex_shader = CompileShader(GL_VERTEX_SHADER, vertexSource)
	fragment_shader = CompileShader(GL_FRAGMENT_SHADER, fragmentSource)

	program = glCreateProgram()
	glAttachShader(program, vertex_shader)
	glAttachShader(program, fragment_shader)
	glBindFragDataLocation(program, 0, "outColor") # optional

	glLinkProgram(program)
	glUseProgram(program)
	return program
end

# Compile the vertex shader
function CompileShader(type::UInt32, source::String)::UInt32
	shader = glCreateShader(type)
	glShaderSource(shader, source)  # nicer thanks to GLAbstraction
	glCompileShader(shader)
	# Check that it compiled correctly
	status = Ref(GLint(0))
	glGetShaderiv(shader, GL_COMPILE_STATUS, status)
	if status[] != GL_TRUE
		buffer = Array(UInt8, 512)
		glGetShaderInfoLog(shader, 512, C_NULL, buffer)
		@error "$(unsafe_string(pointer(buffer), 512))"
	end
	return shader
end

function Bind(ShaderID::UInt32)::Nothing
	glUseProgram(ShaderID)
end

# The vertex shader
vertex_shader = """
#version 150
in vec2 position;

uniform vec2 translation;

void main()
{
	gl_Position = vec4(position + translation, 0.0, 1.0);
}
"""

# The fragment shader
fragment_shader = """
# version 150
uniform vec4 triangleColor;
out vec4 outColor;
void main()
{
	outColor = triangleColor;
}
"""

## VertexArray

struct VertexArray
	ID::Base.RefValue{UInt32}
end

# Create a Vertex Array and make it current
function GenerateVertexArray(VA::VertexArray)
	glGenVertexArrays(1, VA.ID)
	glBindVertexArray(VA.ID[])
end

function Bind(VertexArrayID::Base.RefValue{UInt32})
	glBindVertexArray(VertexArrayID[])
end

# Link vertex data to attributes with the actual binded Vertex Array
function SetVertexArray(AttributeLocation::Int32, AttributeSize::Int64, type::UInt32, normalized::UInt32, stride::Int64, pointer::Ptr)
	glEnableVertexAttribArray(AttributeLocation)
	glVertexAttribPointer(AttributeLocation, AttributeSize, type, normalized, stride, pointer)
end

## Renderer

function Draw(EB::ElementBuffer, VA::VertexArray)
	Bind(VA.ID)
	Bind(GL_ELEMENT_ARRAY_BUFFER, EB.ID)
	glDrawElements(GL_TRIANGLES, 3*EB.NTriangles, GL_UNSIGNED_INT, C_NULL)
end