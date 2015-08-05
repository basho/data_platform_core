.PHONY: all clean deps compile test distclean

all: deps compile

clean:
	$(REBAR) clean

distclean:
	$(REBAR) delete-deps

deps:
	$(REBAR) get-deps
	$(REBAR) compile

compile:
	$(REBAR) skip_deps=true compile

DIALYZER_APPS = erts kernel stdlib sasl eunit compiler crypto public_key

include tools.mk

ifeq ($(REBAR),)
  $(error "Rebar not found. Please set REBAR environment variable or update PATH")
endif
