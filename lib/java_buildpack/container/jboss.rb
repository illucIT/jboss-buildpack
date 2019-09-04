# frozen_string_literal: true

# Cloud Foundry Java Buildpack
# Copyright 2013-2019 the original author or authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'fileutils'
require 'java_buildpack/component/versioned_dependency_component'
require 'java_buildpack/container'
require 'java_buildpack/util/java_main_utils'

module JavaBuildpack
  module Container

    # Encapsulates the detect, compile, and release functionality for applications running Spring Boot CLI
    # applications.
    class Jboss < JavaBuildpack::Component::VersionedDependencyComponent

      # (see JavaBuildpack::Component::BaseComponent#compile)
      def compile
        download_tar
        copy_maria_db_driver
        update_configuration
        copy_application
        copy_additional_libraries
        create_dodeploy
      end

      # (see JavaBuildpack::Component::BaseComponent#release)
      def release
        @droplet.environment_variables.add_environment_variable 'JAVA_OPTS', '$JAVA_OPTS'

        @droplet.java_opts
                .add_system_property('jboss.http.port', '$PORT')
                .add_system_property('java.net.preferIPv4Stack', true)
                .add_system_property('java.net.preferIPv4Addresses', true)

        [
          @droplet.environment_variables.as_env_vars,
          @droplet.java_home.as_env_var,
          'exec',
          "$PWD/#{(@droplet.sandbox + 'bin/standalone.sh').relative_path_from(@droplet.root)}",
          '-b',
          '0.0.0.0'
        ].compact.join(' ')
      end

      protected

      # (see JavaBuildpack::Component::VersionedDependencyComponent#supports?)
      def supports?
        (web_inf? && !JavaBuildpack::Util::JavaMainUtils.main_class(@application)) || ear?
      end

      private

      def copy_application
        FileUtils.mkdir_p root
        @application.root.children.each { |child| FileUtils.cp_r child, root }
      end

      def copy_additional_libraries
        if ear?
          meta_inf_lib = root + "lib"
          @droplet.additional_libraries.each { |additional_library| FileUtils.cp_r additional_library, meta_inf_lib }
        else
          web_inf_lib = root + 'WEB-INF/lib'
          @droplet.additional_libraries.each { |additional_library| FileUtils.cp_r additional_library, web_inf_lib }
        end
      end

      def create_dodeploy
        if ear?
          FileUtils.touch(webapps + 'ROOT.ear.dodeploy')
        else
          FileUtils.touch(webapps + 'ROOT.war.dodeploy')
        end
      end

      def root
        if ear?
          webapps + 'ROOT.ear'
        else
          webapps + 'ROOT.war'
        end
      end

      def update_configuration
        standalone_xml = @droplet.sandbox + 'standalone/configuration/standalone.xml'

        standalone_xml_in_ear = @application.root + 'META-INF/cf/standalone.xml'
        if standalone_xml_in_ear.exist?
          FileUtils.cp(standalone_xml_in_ear, standalone_xml)
        else
          modified = standalone_xml.read
                         .gsub(%r{<location name="/" handler="welcome-content"/>},
                               '<!-- <location name="/" handler="welcome-content"/> -->')

          standalone_xml.open('w') { |f| f.write modified }
        end

        standalone_conf_in_ear = @application.root + 'META-INF/cf/standalone.conf'
        if standalone_conf_in_ear.exist?
          standalone_conf = @droplet.sandbox + 'bin/standalone.conf'
          FileUtils.cp(standalone_conf_in_ear, standalone_conf)
        end
      end

      def copy_maria_db_driver
        maria_db_lib_jar = @application.root + 'lib/mariadb-java-client-2.3.0.jar'
        maria_db_module = @application.root + 'META-INF/cf/module.xml'
        driver_destination = @droplet.sandbox + 'modules/system/layers/base/org/mariadb/mariadb-java-client/main/'
        FileUtils.mkdir_p(driver_destination)
        if maria_db_lib_jar.exist?
          FileUtils.cp(maria_db_lib_jar, driver_destination)
        end
        if maria_db_module.exist?
          FileUtils.cp(maria_db_module, driver_destination)
        end
      end

      def webapps
        @droplet.sandbox + 'standalone/deployments'
      end

      def web_inf?
        (@application.root + 'WEB-INF').exist?
      end

      def ear?
        (@application.root + 'META-INF/application.xml').exist?
      end

    end

  end
end
