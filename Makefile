all: build

build:
	@docker build --tag=boky/postgresql-kitchensink .

release: build
	@docker build --tag=postgresql-kitchensink:$(shell cat VERSION) .
