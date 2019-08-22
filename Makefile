SHELL:=bash

snapshot_sender_version=$(shell cat ./gradle.properties | cut -f2 -d'=')
aws_default_region=eu-west-2
aws_secret_access_key=DummyKey
aws_access_key_id=DummyKey
s3_bucket=demobucket
s3_prefix_folder=test-exporter
data_key_service_url=http://dks-standalone-http:8080
data_key_service_url_ssl=https://dks-standalone-https:8443
follow_flag=--follow

default: help

.PHONY: help
help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

build-jar: ## Build the jar file
	./gradlew build

dist: ## Assemble distribution files in build/dist
	./gradlew assembleDist

add-containers-to-hosts: ## Update laptop hosts file with reference to containers
	./resources/add-containers-to-hosts.sh;

generate-developer-certs:  ## Generate temporary local certs and stores for the local developer containers to use
	pushd resources && ./generate-developer-certs.sh && popd

.PHONY: build-all
build-all: build-jar build-images ## Build the jar file and then all docker images

.PHONY: build-base-images
build-base-images: ## Build base images to avoid rebuilding frequently
	@{ \
		pushd resources; \
		docker build --tag dwp-centos-with-java:latest --file Dockerfile_centos_java . ; \
		docker build --tag dwp-pthon-preinstall:latest --file Dockerfile_python_preinstall . ; \
		popd; \
	}

.PHONY: build-images
build-images: build-base-images ## Build all ecosystem of images
	@{ \
		docker-compose build hbase hbase-populate s3-dummy s3-bucket-provision dks-standalone-http dks-standalone-https snapshot-sender hbase-to-mongo-export mock-nifi snapshot-sender-itest; \
	}

.PHONY: up
up: ## Run the ecosystem of containers
	@{ \
		docker-compose up -d hbase hbase-populate s3-dummy s3-bucket-provision dks-standalone-http dks-standalone-https mock-nifi; \
		echo "Waiting for data to arrive in s3" && sleep 10; \
		docker-compose up -d hbase-to-mongo-export snapshot-sender; \
	}

.PHONY: up-all
up-all: build-images up

.PHONY: hbase-shell
hbase-shell: ## Open an Hbase shell onto the running hbase container
	@{ \
		docker exec -it hbase hbase shell; \
	}

.PHONY: destroy
destroy: ## Bring down the hbase and other services then delete all volumes
	docker-compose down
	docker network prune -f
	docker volume prune -f

.PHONY: integration-all
integration-all: generate-developer-certs build-all up add-containers-to-hosts integration-tests ## Generate certs, build the jar and images, put up the containers, run the integration tests

.PHONY: integration-tests
integration-tests: ## (Re-)Run the integration tests in a Docker container
	@{ \
		export HBASE_TO_MONGO_EXPORT_VERSION=$(hbase_to_mongo_version); \
		export AWS_DEFAULT_REGION=$(aws_default_region); \
		export AWS_ACCESS_KEY_ID=$(aws_access_key_id); \
		export AWS_SECRET_ACCESS_KEY=$(aws_secret_access_key); \
		export S3_BUCKET=$(s3_bucket); \
		export S3_PREFIX_FOLDER=$(s3_prefix_folder); \
		export DATA_KEY_SERVICE_URL=$(data_key_service_url); \
		export DATA_KEY_SERVICE_URL_SSL=$(data_key_service_url_ssl); \
		echo "Waiting for exporters"; \
		sleep 5; \
		docker-compose up snapshot-sender-itest; \
	}
