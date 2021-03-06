# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/python/pip/pip_compile_file_updater"
require "dependabot/shared_helpers"

RSpec.describe Dependabot::FileUpdaters::Python::Pip::PipCompileFileUpdater do
  let(:updater) do
    described_class.new(
      dependency_files: dependency_files,
      dependencies: [dependency],
      credentials: credentials
    )
  end
  let(:dependency_files) { [manifest_file, generated_file] }
  let(:manifest_file) do
    Dependabot::DependencyFile.new(
      name: "requirements/test.in",
      content: fixture("python", "pip_compile_files", manifest_fixture_name)
    )
  end
  let(:generated_file) do
    Dependabot::DependencyFile.new(
      name: "requirements/test.txt",
      content: fixture("python", "requirements", generated_fixture_name)
    )
  end
  let(:manifest_fixture_name) { "unpinned.in" }
  let(:generated_fixture_name) { "pip_compile_unpinned.txt" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      previous_version: dependency_previous_version,
      requirements: dependency_requirements,
      previous_requirements: dependency_previous_requirements,
      package_manager: "pip"
    )
  end
  let(:dependency_name) { "attrs" }
  let(:dependency_version) { "18.1.0" }
  let(:dependency_previous_version) { "17.3.0" }
  let(:dependency_requirements) do
    [{
      file: "requirements/test.in",
      requirement: nil,
      groups: [],
      source: nil
    }]
  end
  let(:dependency_previous_requirements) do
    [{
      file: "requirements/test.in",
      requirement: nil,
      groups: [],
      source: nil
    }]
  end
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:tmp_path) { Dependabot::SharedHelpers::BUMP_TMP_DIR_PATH }

  before { Dir.mkdir(tmp_path) unless Dir.exist?(tmp_path) }

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "updates the requirements.txt" do
      expect(updated_files.count).to eq(1)
      expect(updated_files.first.content).to include("attrs==18.1.0")
      expect(updated_files.first.content).
        to include("pbr==4.0.2                # via mock")
      expect(updated_files.first.content).to include("# This file is autogen")
      expect(updated_files.first.content).to_not include("--hash=sha")
    end

    context "with a custom header" do
      let(:generated_fixture_name) { "pip_compile_custom_header.txt" }

      it "preserves the header" do
        expect(updated_files.count).to eq(1)
        expect(updated_files.first.content).to include("attrs==18.1.0")
        expect(updated_files.first.content).to include("make upgrade")
      end
    end

    context "with hashes" do
      let(:generated_fixture_name) { "pip_compile_hashes.txt" }

      it "updates the requirements.txt, keeping the hashes" do
        expect(updated_files.count).to eq(1)
        expect(updated_files.first.content).to include("attrs==18.1.0")
        expect(updated_files.first.content).to include("4b90b09eeeb9b88c35bc64")
        expect(updated_files.first.content).to include("# This file is autogen")
      end
    end

    context "with an import of the setup.py" do
      let(:dependency_files) { [manifest_file, generated_file, setup_file] }
      let(:setup_file) do
        Dependabot::DependencyFile.new(
          name: "setup.py",
          content: fixture("python", "setup_files", setup_fixture_name)
        )
      end
      let(:manifest_fixture_name) { "imports_setup.in" }
      let(:generated_fixture_name) { "pip_compile_imports_setup.txt" }
      let(:setup_fixture_name) { "small.py" }

      it "updates the requirements.txt" do
        expect(updated_files.count).to eq(1)
        expect(updated_files.first.content).to include("attrs==18.1.0")
        expect(updated_files.first.content).
          to include("pbr==4.0.2                # via mock")
        expect(updated_files.first.content).to include("# This file is autogen")
        expect(updated_files.first.content).to_not include("--hash=sha")
      end

      context "that needs sanitizing" do
        let(:setup_fixture_name) { "small_needs_sanitizing.py" }
        it "updates the requirements.txt" do
          expect(updated_files.count).to eq(1)
          expect(updated_files.first.content).to include("attrs==18.1.0")
        end
      end
    end

    context "with a subdependency" do
      let(:dependency_name) { "pbr" }
      let(:dependency_version) { "4.2.0" }
      let(:dependency_previous_version) { "4.0.2" }
      let(:dependency_requirements) { [] }
      let(:dependency_previous_requirements) { [] }

      it "updates the requirements.txt" do
        expect(updated_files.count).to eq(1)
        expect(updated_files.first.content).
          to include("pbr==4.2.0                # via mock")
      end

      context "with an uncompiled requirement file, too" do
        let(:dependency_files) do
          [manifest_file, generated_file, requirement_file]
        end
        let(:requirement_file) do
          Dependabot::DependencyFile.new(
            name: "requirements.txt",
            content: fixture("python", "requirements", "pbr.txt")
          )
        end
        let(:dependency_requirements) do
          [{
            file: "requirements.txt",
            requirement: "==4.2.0",
            groups: [],
            source: nil
          }]
        end
        let(:dependency_previous_requirements) do
          [{
            file: "requirements.txt",
            requirement: "==4.0.2",
            groups: [],
            source: nil
          }]
        end

        it "updates the requirements.txt" do
          expect(updated_files.count).to eq(2)
          expect(updated_files.first.content).
            to include("pbr==4.2.0                # via mock")
          expect(updated_files.last.content).to include("pbr==4.2.0")
        end
      end
    end

    context "targeting a non-latest version" do
      let(:dependency_version) { "17.4.0" }

      it "updates the requirements.txt" do
        expect(updated_files.count).to eq(1)
        expect(updated_files.first.content).to include("attrs==17.4.0")
        expect(updated_files.first.content).
          to include("pbr==4.0.2                # via mock")
        expect(updated_files.first.content).to include("# This file is autogen")
        expect(updated_files.first.content).to_not include("--hash=sha")
      end
    end

    context "when the requirement.in file needs to be updated" do
      let(:manifest_fixture_name) { "bounded.in" }
      let(:generated_fixture_name) { "pip_compile_bounded.txt" }

      let(:dependency_requirements) do
        [{
          file: "requirements/test.in",
          requirement: "<=18.1.0",
          groups: [],
          source: nil
        }]
      end
      let(:dependency_previous_requirements) do
        [{
          file: "requirements/test.in",
          requirement: "<=17.4.0",
          groups: [],
          source: nil
        }]
      end

      it "updates the requirements.txt and the requirements.in" do
        expect(updated_files.count).to eq(2)
        expect(updated_files.first.content).to include("Attrs<=18.1.0")
        expect(updated_files.last.content).to include("attrs==18.1.0")
        expect(updated_files.last.content).to_not include("# via mock")
      end

      context "with an additional requirements.txt" do
        let(:dependency_files) { [manifest_file, generated_file, other_txt] }
        let(:other_txt) do
          Dependabot::DependencyFile.new(
            name: "requirements.txt",
            content:
              fixture("python", "requirements", "pip_compile_unpinned.txt")
          )
        end

        let(:dependency_requirements) do
          [
            {
              file: "requirements/test.in",
              requirement: "<=18.1.0",
              groups: [],
              source: nil
            },
            {
              file: "requirements.txt",
              requirement: "==18.1.0",
              groups: [],
              source: nil
            }
          ]
        end
        let(:dependency_previous_requirements) do
          [
            {
              file: "requirements/test.in",
              requirement: "<=17.4.0",
              groups: [],
              source: nil
            },
            {
              file: "requirements.txt",
              requirement: "==17.3.0",
              groups: [],
              source: nil
            }
          ]
        end

        it "updates the other requirements.txt, too" do
          expect(updated_files.count).to eq(3)
          expect(updated_files.first.content).to include("Attrs<=18.1.0")
          expect(updated_files[1].content).to include("attrs==18.1.0")
          expect(updated_files.last.content).to include("attrs==18.1.0")
        end
      end
    end

    context "when the upgrade requires Python 2.7" do
      let(:manifest_fixture_name) { "legacy_python.in" }
      let(:generated_fixture_name) { "pip_compile_legacy_python.txt" }

      let(:dependency_name) { "wsgiref" }
      let(:dependency_version) { "0.1.2" }
      let(:dependency_previous_version) { "0.1.1" }
      let(:dependency_requirements) do
        [{
          file: "requirements/test.in",
          requirement: "<=0.1.2",
          groups: [],
          source: nil
        }]
      end
      let(:dependency_previous_requirements) do
        [{
          file: "requirements/test.in",
          requirement: "<=0.1.2",
          groups: [],
          source: nil
        }]
      end

      it "updates the requirements.txt" do
        expect(updated_files.count).to eq(1)
        expect(updated_files.last.content).to include("wsgiref==0.1.2")
      end
    end
  end
end
