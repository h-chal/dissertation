ALL_TESTS := $(basename $(wildcard *.bsv))

BUILDDIR := build_bsim

# Default target: if TEST is given, build only that; else build all
.PHONY: all
all: $(if $(TEST),$(TEST)_sim,$(ALL_TESTS:%=%_sim))

$(BUILDDIR):
	mkdir -p $(BUILDDIR)

build:
	mkdir -p build


%_sim: %_link
	@echo "▶️  Running simulation for $*..."
	@{ \
		OUTPUT=$$(./$(BUILDDIR)/exe_$*_bsim 2>&1); \
		echo "$$OUTPUT"; \
		echo "$$OUTPUT" | grep -q "Dynamic assertion failed"; \
		if [ $$? -eq 0 ]; then \
			echo "❌ Simulation failed for $*"; \
			exit 1; \
		else \
			echo "✅ Completed simulation for $*"; \
		fi; \
	}


%_link: %_compile
	@echo "🔗 Linking $*..."
	bsc -sim -parallel-sim-link 8 \
		-simdir $(BUILDDIR) -bdir build -info-dir build \
		-p ../utils:+ \
		-e mkTest_$* -o ./$(BUILDDIR)/exe_$*_bsim \
		-keep-fires \
		-Xc++ -D_GLIBCXX_USE_CXX11_ABI=0 -Xl -v -Xc -O3 -Xc++ -O3
	@echo "🔗 Linking for $* finished."

%_compile: $(BUILDDIR) build
	@echo "🛠️  Compiling $*.bsv..."
	bsc -u -sim -simdir $(BUILDDIR) -bdir build -info-dir build \
		-use-dpi -keep-fires -aggressive-conditions -no-warn-action-shadowing \
		-no-inline-rwire -show-range-conflict -opt-undetermined-vals \
		-unspecified-to X -show-schedule -check-assert \
		-p ../utils:+ $*.bsv
	@echo "🛠️  Compilation for $* finished."


.PHONY: clean
clean:
	rm -rf $(BUILDDIR) build *.ba *.bo
