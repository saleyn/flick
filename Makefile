all: compile

compile test: deps
	@mix $@

deps:
	mix deps.get

server:
	@PORT=$(if $(port),$(port),8000)
	@echo "Starting HTTP server on port $${PORT}"
	@cd test/js && python3 -m http.server $${PORT}

.PHONY: test
