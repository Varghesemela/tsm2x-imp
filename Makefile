CXX       := g++
HIPCC     := hipcc
STD       := -std=c++11
CCFLAGS   := $(STD) -O3 -g
HIPCCFLAGS := $(STD) -O3 -g
SRC_DIR   := src
OBJ_DIR   := obj

# Add include directory for libwb
INCLUDES  := -I$(PWD)/src/libwb/
# Add library directory for libwb
LIBDIRS   := -L$(PWD)/src/libwb/build/
# Add libwb to the linking flags
LIBS      := -lwb

LINKFLAGS := -lrocblas

DEPLOY    := --amdgpu-target=gfx908

MAIN      := $(SRC_DIR)/multiply.cu
HIPFILES2 := $(SRC_DIR)/kernels.cu
HIPFILES1 := $(filter-out $(MAIN), $(HIPFILES2) $(wildcard $(SRC_DIR)/*.cpp))

HIPOBJS2  := $(HIPFILES2:$(SRC_DIR)/%.cpp=$(OBJ_DIR)/%.o)
HIPOBJS1  := $(HIPFILES1:$(SRC_DIR)/%.cpp=$(OBJ_DIR)/%.o)

OBJS      := $(HIPOBJS1) $(HIPOBJS2)

$(HIPOBJS2): HIPCCFLAGS += $(DEPLOY)
$(HIPOBJS1): HIPCCFLAGS +=

all: ; @$(MAKE) multiply gen print -j

multiply: $(OBJS)
	$(HIPCC) $(HIPCCFLAGS) -lamdhip64 $(DEPLOY) $(LINKFLAGS) $(MAIN) $^ -o $@ 

$(OBJ_DIR)/%.o: $(SRC_DIR)/%.cpp
	$(HIPCC) $(HIPCCFLAGS) -c $< -o $@

gen: gen.cpp
	$(CXX) $(CCFLAGS) $< -o $@

print: print.cpp
	$(CXX) $(CCFLAGS) $< -o $@

.PHONY: clean

clean:
	$(RM) $(OBJS) multiply gen print
