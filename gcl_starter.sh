#!/bin/bash
# =============================================================================
#  GCL STARTER — Fixed for Ubuntu
# =============================================================================
set -e

echo ""
echo "┌─────────────────────────────────────────────────────┐"
echo "│   Game Compiler Lab — Ubuntu Setup (Fixed)           │"
echo "└─────────────────────────────────────────────────────┘"
echo ""

# ── Step 1: Install everything needed ────────────────────────────────────────
echo "[1/4] Installing dependencies..."
sudo apt-get update
sudo apt-get install -y \
    build-essential \
    g++ \
    cmake \
    ninja-build \
    glslang-tools \
    glslang-dev

echo ""
echo "  Verifying installs:"
echo -n "  g++:               "; g++ --version | head -1
echo -n "  cmake:             "; cmake --version | head -1
echo -n "  ninja:             "; ninja --version
if command -v glslangValidator &>/dev/null; then
    echo -n "  glslangValidator:  "; glslangValidator --version 2>/dev/null | head -1
else
    echo "  glslangValidator:  not found (shader stage will be skipped)"
fi
echo ""

# ── Step 2: Create project folder ────────────────────────────────────────────
echo "[2/4] Setting up project in ./gcl_demo/ ..."
mkdir -p gcl_demo
cd gcl_demo

# ── Step 3: Write source files ────────────────────────────────────────────────
echo "[3/4] Writing source files..."

cat > CMakeLists.txt << 'CMAKE'
cmake_minimum_required(VERSION 3.16)
project(gcl_demo CXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
add_executable(gcl_demo main.cpp)
target_compile_options(gcl_demo PRIVATE -Wall -Wextra -O2)
CMAKE

cat > main.cpp << 'CPPSOURCE'
#include <iostream>
#include <fstream>
#include <sstream>
#include <vector>
#include <string>
#include <memory>
#include <unordered_map>
#include <cmath>
#include <iomanip>
#include <algorithm>
#include <functional>
#include <cstring>

// ─────────────────────────────────────────────────────────────────────────────
//  SECTION 1 — GSL LEXER
// ─────────────────────────────────────────────────────────────────────────────
enum class TT {
    Ident,Number,Str,
    KW_entity,KW_onUpdate,KW_onInit,KW_onCollision,
    KW_physics,KW_let,KW_if,KW_return,KW_import,KW_fn,
    LBrace,RBrace,LParen,RParen,
    Semi,Colon,Comma,Dot,Eq,EqEq,Plus,Minus,Star,Slash,Lt,Gt,Arrow,
    Eof,Unknown
};

static const std::unordered_map<std::string,TT> KW={
    {"entity",TT::KW_entity},{"onUpdate",TT::KW_onUpdate},
    {"onInit",TT::KW_onInit},{"onCollision",TT::KW_onCollision},
    {"physics",TT::KW_physics},{"let",TT::KW_let},{"if",TT::KW_if},
    {"return",TT::KW_return},{"import",TT::KW_import},{"fn",TT::KW_fn}
};

struct Token{
    TT type; std::string lex; int line;
    std::string name()const{
        switch(type){
            case TT::Ident:return"Identifier";case TT::Number:return"Number";
            case TT::Str:return"String";case TT::KW_entity:return"kw:entity";
            case TT::KW_onUpdate:return"kw:onUpdate";case TT::KW_onInit:return"kw:onInit";
            case TT::KW_onCollision:return"kw:onCollision";case TT::KW_physics:return"kw:physics";
            case TT::KW_let:return"kw:let";case TT::KW_if:return"kw:if";
            case TT::KW_return:return"kw:return";case TT::KW_import:return"kw:import";
            case TT::KW_fn:return"kw:fn";case TT::LBrace:return"{";
            case TT::RBrace:return"}";case TT::LParen:return"(";
            case TT::RParen:return")";case TT::Semi:return";";
            case TT::Colon:return":";case TT::Comma:return",";
            case TT::Dot:return".";case TT::Eq:return"=";
            case TT::EqEq:return"==";case TT::Plus:return"+";
            case TT::Minus:return"-";case TT::Star:return"*";
            case TT::Slash:return"/";case TT::Lt:return"<";
            case TT::Gt:return">";case TT::Arrow:return"->";
            case TT::Eof:return"EOF";default:return"?";
        }
    }
};

class Lexer{
    std::string src; size_t pos=0; int line=1;
    bool end()const{return pos>=src.size();}
    char peek(int o=0)const{return(pos+o<src.size())?src[pos+o]:'\0';}
    char eat(){return src[pos++];}
    void skipWS(){
        while(!end()){
            if(peek()=='\n'){++line;++pos;}
            else if(peek()==' '||peek()=='\t'||peek()=='\r'){++pos;}
            else if(peek()=='/'&&peek(1)=='/'){while(!end()&&peek()!='\n')++pos;}
            else break;
        }
    }
public:
    explicit Lexer(std::string s):src(std::move(s)){}
    std::vector<Token> tokenize(){
        std::vector<Token> out;
        while(true){
            skipWS(); if(end())break;
            int ln=line; char c=eat();
            if(c=='"'){std::string v;while(!end()&&peek()!='"')v+=eat();if(!end())eat();out.push_back({TT::Str,v,ln});continue;}
            if(isdigit(c)||(c=='.'&&isdigit(peek()))){std::string n(1,c);while(!end()&&(isdigit(peek())||peek()=='.'))n+=eat();out.push_back({TT::Number,n,ln});continue;}
            if(isalpha(c)||c=='_'){std::string id(1,c);while(!end()&&(isalnum(peek())||peek()=='_'))id+=eat();auto it=KW.find(id);out.push_back({it!=KW.end()?it->second:TT::Ident,id,ln});continue;}
            if(c=='-'&&peek()=='>'){eat();out.push_back({TT::Arrow,"->",ln});continue;}
            if(c=='='&&peek()=='='){eat();out.push_back({TT::EqEq,"==",ln});continue;}
            TT t=TT::Unknown; std::string l(1,c);
            switch(c){case'{':t=TT::LBrace;break;case'}':t=TT::RBrace;break;
                case'(':t=TT::LParen;break;case')':t=TT::RParen;break;
                case';':t=TT::Semi;break;case':':t=TT::Colon;break;
                case',':t=TT::Comma;break;case'.':t=TT::Dot;break;
                case'=':t=TT::Eq;break;case'+':t=TT::Plus;break;
                case'-':t=TT::Minus;break;case'*':t=TT::Star;break;
                case'/':t=TT::Slash;break;case'<':t=TT::Lt;break;
                case'>':t=TT::Gt;break;default:break;}
            out.push_back({t,l,ln});
        }
        out.push_back({TT::Eof,"",line});
        return out;
    }
};

// ─────────────────────────────────────────────────────────────────────────────
//  SECTION 2 — GSL PARSER → AST
// ─────────────────────────────────────────────────────────────────────────────
struct Node{
    std::string kind,val;
    std::vector<std::shared_ptr<Node>> ch;
    void print(int d=0)const{
        std::string p(d*2,' ');
        std::cout<<p<<"("<<kind;
        if(!val.empty())std::cout<<" \""<<val<<"\"";
        if(!ch.empty()){std::cout<<"\n";for(auto&c:ch)c->print(d+1);std::cout<<p;}
        std::cout<<")\n";
    }
};
using NP=std::shared_ptr<Node>;
NP mk(const std::string&k,const std::string&v=""){auto n=std::make_shared<Node>();n->kind=k;n->val=v;return n;}

class Parser{
    std::vector<Token> tok; size_t pos=0;
    bool end()const{return tok[pos].type==TT::Eof;}
    Token&cur(){return tok[pos];}
    bool is(TT t)const{return tok[pos].type==t;}
    Token eat(){return tok[pos++];}
    Token expect(TT t,const char*ctx=""){
        if(!is(t))std::cerr<<"[ParseError] line "<<cur().line<<" ("<<ctx<<"): got '"<<cur().lex<<"'\n";
        return eat();
    }
public:
    explicit Parser(std::vector<Token>t):tok(std::move(t)){}
    NP parseProgram(){
        auto prog=mk("Program");
        while(!end()){
            if(is(TT::KW_import)){eat();prog->ch.push_back(mk("Import",eat().lex));}
            else if(is(TT::KW_entity))prog->ch.push_back(parseEntity());
            else eat();
        }
        return prog;
    }
private:
    NP parseEntity(){
        expect(TT::KW_entity,"entity");
        auto e=mk("Entity",eat().lex);
        expect(TT::LBrace,"entity body");
        while(!end()&&!is(TT::RBrace)){
            if(is(TT::KW_let))e->ch.push_back(parseLet());
            else if(is(TT::KW_physics))e->ch.push_back(parsePhysics());
            else if(is(TT::KW_onUpdate)||is(TT::KW_onInit)||is(TT::KW_onCollision))e->ch.push_back(parseHandler());
            else eat();
        }
        expect(TT::RBrace,"entity end");
        return e;
    }
    NP parseLet(){
        expect(TT::KW_let,"let");
        auto d=mk("LetDecl",eat().lex);
        if(is(TT::Colon)){eat();d->ch.push_back(mk("Type",eat().lex));}
        if(is(TT::Eq)){eat();d->ch.push_back(parseExpr());}
        if(is(TT::Semi))eat();
        return d;
    }
    NP parsePhysics(){
        expect(TT::KW_physics,"physics");
        auto b=mk("PhysicsBlock");
        expect(TT::LBrace,"physics body");
        while(!end()&&!is(TT::RBrace)){
            auto key=eat().lex;
            if(is(TT::Colon))eat();
            auto f=mk("Field",key);f->ch.push_back(parseExpr());b->ch.push_back(f);
            if(is(TT::Comma))eat();
        }
        expect(TT::RBrace,"physics end");
        return b;
    }
    NP parseHandler(){
        auto h=mk("Handler",eat().lex);
        if(is(TT::LParen)){
            eat();
            while(!end()&&!is(TT::RParen)){
                auto p=mk("Param",eat().lex);
                if(is(TT::Colon)){eat();p->ch.push_back(mk("Type",eat().lex));}
                h->ch.push_back(p);if(is(TT::Comma))eat();
            }
            expect(TT::RParen,"handler params");
        }
        expect(TT::LBrace,"handler body");
        while(!end()&&!is(TT::RBrace))h->ch.push_back(parseStmt());
        expect(TT::RBrace,"handler end");
        return h;
    }
    NP parseStmt(){
        if(is(TT::KW_let))return parseLet();
        if(is(TT::KW_if))return parseIf();
        if(is(TT::KW_return)){eat();auto r=mk("Return");if(!is(TT::Semi))r->ch.push_back(parseExpr());if(is(TT::Semi))eat();return r;}
        auto e=parseExpr();if(is(TT::Semi))eat();return e;
    }
    NP parseIf(){
        expect(TT::KW_if,"if");expect(TT::LParen,"if cond");
        auto n=mk("IfStmt");n->ch.push_back(parseExpr());
        expect(TT::RParen,"if cond");expect(TT::LBrace,"if body");
        while(!end()&&!is(TT::RBrace))n->ch.push_back(parseStmt());
        expect(TT::RBrace,"if end");return n;
    }
    NP parseExpr(){
        auto L=parsePrimary();
        while(is(TT::Plus)||is(TT::Minus)||is(TT::Star)||is(TT::Slash)||is(TT::EqEq)||is(TT::Lt)||is(TT::Gt)){
            auto op=eat().lex;auto R=parsePrimary();auto b=mk("BinOp",op);b->ch.push_back(L);b->ch.push_back(R);L=b;
        }
        return L;
    }
    NP parsePrimary(){
        if(is(TT::Number))return mk("Num",eat().lex);
        if(is(TT::Str))return mk("Str",eat().lex);
        if(is(TT::Ident)){
            auto name=eat().lex;
            if(is(TT::LParen)){eat();auto c=mk("Call",name);while(!end()&&!is(TT::RParen)){c->ch.push_back(parseExpr());if(is(TT::Comma))eat();}expect(TT::RParen,"call");return c;}
            if(is(TT::Dot)){eat();auto m=eat().lex;auto a=mk("Access",name+"."+m);if(is(TT::LParen)){eat();while(!end()&&!is(TT::RParen)){a->ch.push_back(parseExpr());if(is(TT::Comma))eat();}expect(TT::RParen,"access call");}return a;}
            return mk("Ident",name);
        }
        if(is(TT::LParen)){eat();auto e=parseExpr();expect(TT::RParen,"group");return e;}
        if(is(TT::Minus)){eat();auto n=mk("Neg");n->ch.push_back(parsePrimary());return n;}
        return mk("Unknown",eat().lex);
    }
};

// ─────────────────────────────────────────────────────────────────────────────
//  SECTION 3 — PHYSICS SIMULATION
// ─────────────────────────────────────────────────────────────────────────────
struct V3{
    float x,y,z;
    V3 operator+(V3 o)const{return{x+o.x,y+o.y,z+o.z};}
    V3 operator-(V3 o)const{return{x-o.x,y-o.y,z-o.z};}
    V3 operator*(float s)const{return{x*s,y*s,z*s};}
    float dot(V3 o)const{return x*o.x+y*o.y+z*o.z;}
    float len()const{return std::sqrt(dot(*this));}
    V3 norm()const{float l=len();return l>1e-6f?(*this)*(1.f/l):V3{0,0,0};}
};
std::ostream&operator<<(std::ostream&os,V3 v){
    return os<<std::fixed<<std::setprecision(3)
             <<"("<<std::setw(7)<<v.x<<", "<<std::setw(7)<<v.y<<", "<<std::setw(7)<<v.z<<")";
}
struct Body{std::string name;V3 pos,vel;float mass,rest,rad;};
struct World{
    static constexpr float G=-9.81f;
    std::vector<Body> bodies;
    void step(float dt){
        for(auto&b:bodies){
            b.vel=b.vel+V3{0,G,0}*dt;
            b.pos=b.pos+b.vel*dt;
            if(b.pos.y<b.rad){b.pos.y=b.rad;if(b.vel.y<0){b.vel.y=-b.vel.y*b.rest;b.vel.x*=0.97f;b.vel.z*=0.97f;}}
        }
        for(size_t i=0;i<bodies.size();++i)
            for(size_t j=i+1;j<bodies.size();++j)
                collide(bodies[i],bodies[j]);
    }
    void collide(Body&a,Body&b){
        V3 d=b.pos-a.pos;float dist=d.len(),minD=a.rad+b.rad;
        if(dist>=minD||dist<1e-6f)return;
        V3 n=d.norm();float pen=minD-dist,tm=a.mass+b.mass;
        a.pos=a.pos-n*(pen*b.mass/tm);b.pos=b.pos+n*(pen*a.mass/tm);
        float rv=(b.vel-a.vel).dot(n);if(rv>0)return;
        float e=std::min(a.rest,b.rest);
        float j=-(1+e)*rv/(1/a.mass+1/b.mass);
        a.vel=a.vel-n*(j/a.mass);b.vel=b.vel+n*(j/b.mass);
    }
};

void runPhysics(){
    std::cout<<"\n╔══════════════════════════════════════════════════════════════╗\n";
    std::cout<<"║  GCL-Phys  —  Rigid Body Simulation                          ║\n";
    std::cout<<"╚══════════════════════════════════════════════════════════════╝\n\n";
    std::cout<<"  3 spheres, gravity 9.81 m/s², floor bounce, sphere collisions\n\n";
    World w;
    w.bodies.push_back({"BallA",{0,10,0},{1.5f,0,0},1.0f,0.7f,0.5f});
    w.bodies.push_back({"BallB",{3, 8,0},{-0.5f,0,0},2.0f,0.5f,0.6f});
    w.bodies.push_back({"BallC",{1.5f,15,0},{0,0,0},0.5f,0.9f,0.3f});
    const float dt=1.f/60.f; const int F=180,PE=30;
    std::cout<<std::left<<std::setw(6)<<"Frame"<<std::setw(8)<<"t(s)"
             <<std::setw(7)<<"Body"<<std::setw(28)<<"  Position"<<std::setw(28)<<"  Velocity"<<"\n";
    std::cout<<"  "<<std::string(72,'-')<<"\n";
    for(int f=0;f<=F;++f){
        if(f%PE==0){
            for(auto&b:w.bodies){
                std::ostringstream ps,vs;ps<<b.pos;vs<<b.vel;
                std::cout<<std::left<<std::setw(6)<<f
                         <<std::setw(8)<<std::fixed<<std::setprecision(2)<<(f*dt)
                         <<std::setw(7)<<b.name<<std::setw(28)<<ps.str()<<std::setw(28)<<vs.str()<<"\n";
            }
            std::cout<<"\n";
        }
        w.step(dt);
    }
    std::cout<<"  Simulated "<<F<<" frames ("<<F/60<<"s at 60Hz)\n";
}

// ─────────────────────────────────────────────────────────────────────────────
//  SECTION 4 — SHADER COMPILATION
// ─────────────────────────────────────────────────────────────────────────────
const char*VERT=R"GLSL(
#version 450
layout(location=0) in vec3 inPos;
layout(location=1) in vec3 inNormal;
layout(location=2) in vec2 inUV;
layout(location=0) out vec3 fragPos;
layout(location=1) out vec3 fragNormal;
layout(location=2) out vec2 fragUV;
layout(set=0,binding=0) uniform UBO{mat4 model;mat4 view;mat4 proj;} ubo;
void main(){
    vec4 wp=ubo.model*vec4(inPos,1.0);
    fragPos=wp.xyz;
    fragNormal=mat3(transpose(inverse(ubo.model)))*inNormal;
    fragUV=inUV;
    gl_Position=ubo.proj*ubo.view*wp;
}
)GLSL";

const char*FRAG=R"GLSL(
#version 450
layout(location=0) in vec3 fragPos;
layout(location=1) in vec3 fragNormal;
layout(location=2) in vec2 fragUV;
layout(location=0) out vec4 outColor;
layout(set=0,binding=1) uniform Light{vec3 pos;vec3 color;float ambient;float specPow;} L;
layout(set=0,binding=2) uniform sampler2D albedo;
void main(){
    vec3 N=normalize(fragNormal);
    vec3 Ldir=normalize(L.pos-fragPos);
    vec3 V=normalize(-fragPos);
    vec3 H=normalize(Ldir+V);
    float diff=max(dot(N,Ldir),0.0);
    float spec=pow(max(dot(N,H),0.0),L.specPow);
    vec3 tex=texture(albedo,fragUV).rgb;
    outColor=vec4((L.ambient+diff+spec)*L.color*tex,1.0);
}
)GLSL";

const char*BAD=R"GLSL(
#version 450
layout(location=0) out vec4 outColor;
void main(){ outColor=vec4(undeclaredVar  1.0) }
)GLSL";

void writeFile(const char*path,const char*src){std::ofstream f(path);f<<src;}
void validate(const char*path,const char*label){
    std::string cmd=std::string("glslangValidator ")+path+" 2>&1";
    std::cout<<"  Compiling: "<<label<<"\n";
    FILE*p=popen(cmd.c_str(),"r");if(!p){std::cerr<<"  popen failed\n";return;}
    char buf[512];std::string out;while(fgets(buf,sizeof(buf),p))out+=buf;
    int ret=pclose(p);
    if(ret==0){std::cout<<"  \033[32m[PASS]\033[0m  valid GLSL\n\n";}
    else{
        std::cout<<"  \033[31m[FAIL]\033[0m  errors:\n";
        std::istringstream ss(out);std::string ln;
        while(std::getline(ss,ln))if(!ln.empty())std::cout<<"    | "<<ln<<"\n";
        std::cout<<"\n";
    }
}
void runShaders(){
    std::cout<<"\n╔══════════════════════════════════════════════════════════════╗\n";
    std::cout<<"║  GCL Shader Pipeline  —  GLSL via glslangValidator           ║\n";
    std::cout<<"╚══════════════════════════════════════════════════════════════╝\n\n";
    if(system("which glslangValidator > /dev/null 2>&1")!=0){
        std::cout<<"  [Skip] glslangValidator not found.\n";
        std::cout<<"  Run:   sudo apt install glslang-tools\n\n";
        return;
    }
    writeFile("/tmp/gcl.vert",VERT);writeFile("/tmp/gcl.frag",FRAG);writeFile("/tmp/gcl_bad.frag",BAD);
    std::cout<<"  Valid shaders (Blinn-Phong + texture):\n";
    std::cout<<"  "<<std::string(48,'-')<<"\n";
    validate("/tmp/gcl.vert","Vertex   shader — transform, normals");
    validate("/tmp/gcl.frag","Fragment shader — Blinn-Phong + sampler");
    std::cout<<"  Intentionally broken shader:\n";
    std::cout<<"  "<<std::string(48,'-')<<"\n";
    validate("/tmp/gcl_bad.frag","Bad frag — undeclared var + missing semicolon");
}

// ─────────────────────────────────────────────────────────────────────────────
//  MAIN
// ─────────────────────────────────────────────────────────────────────────────
static const char*GSL=R"GSL(
import physics;
import input;

entity Player {
    let speed: f32 = 5.0;
    let health: i32 = 100;

    physics {
        mass:        70.0,
        restitution: 0.3,
        collider:    Capsule(radius: 0.4, height: 1.8)
    }

    onInit {
        log("Player spawned");
    }

    onUpdate {
        let dir = input.wasdVector();
        move(dir * speed * deltaTime);
    }

    onCollision(other: Entity, contact: ContactPoint) {
        if (health <= 0) {
            destroy(self);
        }
    }
}

entity Enemy {
    let damage: f32 = 10.0;

    physics { mass: 80.0, restitution: 0.2 }

    onUpdate {
        let p = findNearest("Player");
        moveToward(p * 2.0 * deltaTime);
    }
}
)GSL";

int main(){
    std::cout<<"\n  \033[36m╔══════════════════════════════════╗\033[0m\n";
    std::cout<<"  \033[36m║   Game Compiler Lab  —  GCL Demo  ║\033[0m\n";
    std::cout<<"  \033[36m╚══════════════════════════════════╝\033[0m\n\n";

    // Stage 1: Lexer
    std::cout<<"╔══════════════════════════════════════════════════════════════╗\n";
    std::cout<<"║  Stage 1: Lexer  —  GSL source → tokens                      ║\n";
    std::cout<<"╚══════════════════════════════════════════════════════════════╝\n\n";
    Lexer lex(GSL);
    auto tokens=lex.tokenize();
    int lines=(int)std::count(GSL,GSL+strlen(GSL),'\n');
    std::cout<<"  Script: "<<lines<<" lines  →  "<<(tokens.size()-1)<<" tokens\n\n";
    std::cout<<"  First 30 tokens:\n  "<<std::string(42,'-')<<"\n";
    for(size_t i=0;i<std::min((size_t)30,tokens.size()-1);++i)
        std::cout<<"  ["<<std::setw(2)<<i+1<<"]  "<<std::left<<std::setw(16)<<tokens[i].name()<<"  '"<<tokens[i].lex<<"'\n";
    std::cout<<"  ... ("<<tokens.size()-1<<" tokens total)\n";

    // Stage 2: Parser
    std::cout<<"\n╔══════════════════════════════════════════════════════════════╗\n";
    std::cout<<"║  Stage 2: Parser  —  tokens → Abstract Syntax Tree           ║\n";
    std::cout<<"╚══════════════════════════════════════════════════════════════╝\n\n";
    Parser parser(tokens);
    auto ast=parser.parseProgram();
    ast->print(1);
    std::function<int(const NP&)> cnt=[&](const NP&n)->int{int c=1;for(auto&ch:n->ch)c+=cnt(ch);return c;};
    std::cout<<"  Total AST nodes: "<<cnt(ast)<<"\n";

    // Stage 3: Physics
    runPhysics();

    // Stage 4: Shaders
    runShaders();

    std::cout<<"\n╔══════════════════════════════════════════════════════════════╗\n";
    std::cout<<"║  All 4 stages complete!                                       ║\n";
    std::cout<<"║  Stage 1  Lexer    ✓   Stage 2  Parser   ✓                   ║\n";
    std::cout<<"║  Stage 3  Physics  ✓   Stage 4  Shaders  ✓                   ║\n";
    std::cout<<"║                                                               ║\n";
    std::cout<<"║  Next: wire the PhysicsBlock AST node → RigidBody             ║\n";
    std::cout<<"╚══════════════════════════════════════════════════════════════╝\n\n";
    return 0;
}
CPPSOURCE

echo "  main.cpp         written ✓"
echo "  CMakeLists.txt   written ✓"

# ── Step 4: Build ─────────────────────────────────────────────────────────────
echo ""
echo "[4/4] Building..."
echo ""
mkdir -p build && cd build
if command -v ninja &>/dev/null; then
    echo "  Using: Ninja"
    cmake .. -G Ninja -DCMAKE_BUILD_TYPE=Release 2>&1
    ninja 2>&1
else
    echo "  Ninja not found, using Make"
    cmake .. -DCMAKE_BUILD_TYPE=Release 2>&1
    make -j$(nproc) 2>&1
fi
cd ..

echo ""
echo "══════════════════════════════════════════════════════════"
echo "  Build successful!"
echo "  To run again later:"
echo "    cd gcl_demo && ./build/gcl_demo"
echo "══════════════════════════════════════════════════════════"
echo ""
./build/gcl_demo
