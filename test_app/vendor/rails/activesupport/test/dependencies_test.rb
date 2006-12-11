require File.dirname(__FILE__) + '/abstract_unit'
require 'pp'

module ModuleWithMissing
  mattr_accessor :missing_count
  def self.const_missing(name)
    self.missing_count += 1
    name
  end
end

class DependenciesTest < Test::Unit::TestCase
  
  def teardown
    Dependencies.clear
  end

  def with_loading(*from)
    old_mechanism, Dependencies.mechanism = Dependencies.mechanism, :load
    dir = File.dirname(__FILE__)
    prior_load_paths = Dependencies.load_paths
    Dependencies.load_paths = from.collect { |f| "#{dir}/#{f}" }
    yield
  ensure
    Dependencies.load_paths = prior_load_paths
    Dependencies.mechanism = old_mechanism
  end

  def test_tracking_loaded_files
    require_dependency(File.dirname(__FILE__) + "/dependencies/service_one")
    require_dependency(File.dirname(__FILE__) + "/dependencies/service_two")
    assert_equal 2, Dependencies.loaded.size
  end

  def test_tracking_identical_loaded_files
    require_dependency(File.dirname(__FILE__) + "/dependencies/service_one")
    require_dependency(File.dirname(__FILE__) + "/dependencies/service_one")
    assert_equal 1, Dependencies.loaded.size
  end

  def test_missing_dependency_raises_missing_source_file
    assert_raises(MissingSourceFile) { require_dependency("missing_service") }
  end

  def test_missing_association_raises_nothing
    assert_nothing_raised { require_association("missing_model") }
  end

  def test_dependency_which_raises_exception_isnt_added_to_loaded_set
    with_loading do
      filename = "#{File.dirname(__FILE__)}/dependencies/raises_exception"
      $raises_exception_load_count = 0

      5.times do |count|
        assert_raises(Exception) { require_dependency filename }
        assert_equal count + 1, $raises_exception_load_count

        assert !Dependencies.loaded.include?(filename)
        assert !Dependencies.history.include?(filename)
      end
    end
  end

  def test_warnings_should_be_enabled_on_first_load
    with_loading 'dependencies' do
      old_warnings, Dependencies.warnings_on_first_load = Dependencies.warnings_on_first_load, true

      filename = "check_warnings"
      expanded = File.expand_path("test/dependencies/#{filename}")
      $check_warnings_load_count = 0

      assert !Dependencies.loaded.include?(expanded)
      assert !Dependencies.history.include?(expanded)

      silence_warnings { require_dependency filename }
      assert_equal 1, $check_warnings_load_count
      assert_equal true, $checked_verbose, 'On first load warnings should be enabled.'

      assert Dependencies.loaded.include?(expanded)
      Dependencies.clear
      assert !Dependencies.loaded.include?(expanded)
      assert Dependencies.history.include?(expanded)

      silence_warnings { require_dependency filename }
      assert_equal 2, $check_warnings_load_count
      assert_equal nil, $checked_verbose, 'After first load warnings should be left alone.'

      assert Dependencies.loaded.include?(expanded)
      Dependencies.clear
      assert !Dependencies.loaded.include?(expanded)
      assert Dependencies.history.include?(expanded)

      enable_warnings { require_dependency filename }
      assert_equal 3, $check_warnings_load_count
      assert_equal true, $checked_verbose, 'After first load warnings should be left alone.'

      assert Dependencies.loaded.include?(expanded)
    end
  end

  def test_mutual_dependencies_dont_infinite_loop
    with_loading 'dependencies' do
      $mutual_dependencies_count = 0
      assert_nothing_raised { require_dependency 'mutual_one' }
      assert_equal 2, $mutual_dependencies_count

      Dependencies.clear

      $mutual_dependencies_count = 0
      assert_nothing_raised { require_dependency 'mutual_two' }
      assert_equal 2, $mutual_dependencies_count
    end
  end

  def test_as_load_path
    assert_equal '', DependenciesTest.as_load_path
  end

  def test_module_loading
    with_loading 'autoloading_fixtures' do
      assert_kind_of Module, A
      assert_kind_of Class, A::B
      assert_kind_of Class, A::C::D
      assert_kind_of Class, A::C::E::F
    end
  end

  def test_non_existing_const_raises_name_error
    with_loading 'autoloading_fixtures' do
      assert_raises(NameError) { DoesNotExist }
      assert_raises(NameError) { NoModule::DoesNotExist }
      assert_raises(NameError) { A::DoesNotExist }
      assert_raises(NameError) { A::B::DoesNotExist }
    end
  end

  def test_directories_manifest_as_modules_unless_const_defined
    with_loading 'autoloading_fixtures' do
      assert_kind_of Module, ModuleFolder
      Object.send :remove_const, :ModuleFolder
    end
  end

  def test_module_with_nested_class
    with_loading 'autoloading_fixtures' do
      assert_kind_of Class, ModuleFolder::NestedClass
      Object.send :remove_const, :ModuleFolder
    end
  end

  def test_module_with_nested_inline_class
    with_loading 'autoloading_fixtures' do
      assert_kind_of Class, ModuleFolder::InlineClass
      Object.send :remove_const, :ModuleFolder
    end
  end

  def test_directories_may_manifest_as_nested_classes
    with_loading 'autoloading_fixtures' do
      assert_kind_of Class, ClassFolder
      Object.send :remove_const, :ClassFolder
    end
  end

  def test_class_with_nested_class
    with_loading 'autoloading_fixtures' do
      assert_kind_of Class, ClassFolder::NestedClass
      Object.send :remove_const, :ClassFolder
    end
  end

  def test_class_with_nested_inline_class
    with_loading 'autoloading_fixtures' do
      assert_kind_of Class, ClassFolder::InlineClass
      Object.send :remove_const, :ClassFolder
    end
  end

  def test_nested_class_can_access_sibling
    with_loading 'autoloading_fixtures' do
      sibling = ModuleFolder::NestedClass.class_eval "NestedSibling"
      assert defined?(ModuleFolder::NestedSibling)
      assert_equal ModuleFolder::NestedSibling, sibling
      Object.send :remove_const, :ModuleFolder
    end
  end

  def failing_test_access_thru_and_upwards_fails
    with_loading 'autoloading_fixtures' do
      assert ! defined?(ModuleFolder)
      assert_raises(NameError) { ModuleFolder::Object }
      assert_raises(NameError) { ModuleFolder::NestedClass::Object }
      Object.send :remove_const, :ModuleFolder
    end
  end
  
  def test_non_existing_const_raises_name_error_with_fully_qualified_name
    with_loading 'autoloading_fixtures' do
      begin
        A::DoesNotExist.nil?
        flunk "No raise!!"
      rescue NameError => e
        assert_equal "uninitialized constant A::DoesNotExist", e.message
      end
      begin
        A::B::DoesNotExist.nil?
        flunk "No raise!!"
      rescue NameError => e
        assert_equal "uninitialized constant A::B::DoesNotExist", e.message
      end
    end
  end
  
  def test_smart_name_error_strings
    begin
      Object.module_eval "ImaginaryObject"
      flunk "No raise!!"
    rescue NameError => e
      assert e.message.include?("uninitialized constant ImaginaryObject")
    end
  end
  
  def test_loadable_constants_for_path_should_handle_empty_autoloads
    assert_equal [], Dependencies.loadable_constants_for_path('hello')
  end
  
  def test_loadable_constants_for_path_should_handle_relative_paths
    fake_root = 'dependencies'
    relative_root = File.dirname(__FILE__) + '/dependencies'
    ['', '/'].each do |suffix|
      with_loading fake_root + suffix do
        assert_equal ["A::B"], Dependencies.loadable_constants_for_path(relative_root + '/a/b')
      end
    end
  end
  
  def test_loadable_constants_for_path_should_provide_all_results
    fake_root = '/usr/apps/backpack'
    with_loading fake_root, fake_root + '/lib' do
      root = Dependencies.load_paths.first
      assert_equal ["Lib::A::B", "A::B"], Dependencies.loadable_constants_for_path(root + '/lib/a/b')
    end
  end
  
  def test_loadable_constants_for_path_should_uniq_results
    fake_root = '/usr/apps/backpack/lib'
    with_loading fake_root, fake_root + '/' do
      root = Dependencies.load_paths.first
      assert_equal ["A::B"], Dependencies.loadable_constants_for_path(root + '/a/b')
    end
  end
  
  def test_loadable_constants_with_load_path_without_trailing_slash
    path = File.dirname(__FILE__) + '/autoloading_fixtures/class_folder/inline_class.rb'
    with_loading 'autoloading_fixtures/class/' do
      assert_equal [], Dependencies.loadable_constants_for_path(path)
    end
  end
  
  def test_qualified_const_defined
    assert Dependencies.qualified_const_defined?("Object")
    assert Dependencies.qualified_const_defined?("::Object")
    assert Dependencies.qualified_const_defined?("::Object::Kernel")
    assert Dependencies.qualified_const_defined?("::Object::Dependencies")
    assert Dependencies.qualified_const_defined?("::Test::Unit::TestCase")
  end
  
  def test_qualified_const_defined_should_not_call_method_missing
    ModuleWithMissing.missing_count = 0
    assert ! Dependencies.qualified_const_defined?("ModuleWithMissing::A")
    assert_equal 0, ModuleWithMissing.missing_count
    assert ! Dependencies.qualified_const_defined?("ModuleWithMissing::A::B")
    assert_equal 0, ModuleWithMissing.missing_count
  end
  
  def test_autoloaded?
    with_loading 'autoloading_fixtures' do
      assert ! Dependencies.autoloaded?("ModuleFolder")
      assert ! Dependencies.autoloaded?("ModuleFolder::NestedClass")
      
      assert Dependencies.autoloaded?(ModuleFolder)
      
      assert Dependencies.autoloaded?("ModuleFolder")
      assert ! Dependencies.autoloaded?("ModuleFolder::NestedClass")
      
      assert Dependencies.autoloaded?(ModuleFolder::NestedClass)
      
      assert Dependencies.autoloaded?("ModuleFolder")
      assert Dependencies.autoloaded?("ModuleFolder::NestedClass")
      
      assert Dependencies.autoloaded?("::ModuleFolder")
      assert Dependencies.autoloaded?(:ModuleFolder)
      
      Object.send :remove_const, :ModuleFolder
    end
  end
  
  def test_qualified_name_for
    assert_equal "A", Dependencies.qualified_name_for(Object, :A)
    assert_equal "A", Dependencies.qualified_name_for(:Object, :A)
    assert_equal "A", Dependencies.qualified_name_for("Object", :A)
    assert_equal "A", Dependencies.qualified_name_for("::Object", :A)
    assert_equal "A", Dependencies.qualified_name_for("::Kernel", :A)
    
    assert_equal "Dependencies::A", Dependencies.qualified_name_for(:Dependencies, :A)
    assert_equal "Dependencies::A", Dependencies.qualified_name_for(Dependencies, :A)
  end
  
  def test_file_search
    with_loading 'dependencies' do
      root = Dependencies.load_paths.first
      assert_equal nil, Dependencies.search_for_file('service_three')
      assert_equal nil, Dependencies.search_for_file('service_three.rb')
      assert_equal root + '/service_one.rb', Dependencies.search_for_file('service_one')
      assert_equal root + '/service_one.rb', Dependencies.search_for_file('service_one.rb')
    end
  end
  
  def test_file_search_uses_first_in_load_path
    with_loading 'dependencies', 'autoloading_fixtures' do
      deps, autoload = Dependencies.load_paths
      assert_match %r/dependencies/, deps
      assert_match %r/autoloading_fixtures/, autoload
      
      assert_equal deps + '/conflict.rb', Dependencies.search_for_file('conflict')
    end
    with_loading 'autoloading_fixtures', 'dependencies' do
      autoload, deps = Dependencies.load_paths
      assert_match %r/dependencies/, deps
      assert_match %r/autoloading_fixtures/, autoload
      
      assert_equal autoload + '/conflict.rb', Dependencies.search_for_file('conflict')
    end
    
  end
    
  def test_custom_const_missing_should_work
    Object.module_eval <<-end_eval
      module ModuleWithCustomConstMissing
        def self.const_missing(name)
          const_set name, name.to_s.hash
        end

        module A
        end
      end
    end_eval
    
    with_loading 'autoloading_fixtures' do
      assert_kind_of Integer, ::ModuleWithCustomConstMissing::B
      assert_kind_of Module, ::ModuleWithCustomConstMissing::A
      assert_kind_of String, ::ModuleWithCustomConstMissing::A::B
    end
  end
  
  def test_const_missing_should_not_double_load
    $counting_loaded_times = 0
    with_loading 'autoloading_fixtures' do
      require_dependency '././counting_loader'
      assert_equal 1, $counting_loaded_times
      assert_raises(ArgumentError) { Dependencies.load_missing_constant Object, :CountingLoader }
      assert_equal 1, $counting_loaded_times
    end
  end
  
  def test_const_missing_within_anonymous_module
    $counting_loaded_times = 0
    m = Module.new
    m.module_eval "def a() CountingLoader; end"
    extend m
    kls = nil    
    with_loading 'autoloading_fixtures' do
      kls = nil
      assert_nothing_raised { kls = a }
      assert_equal "CountingLoader", kls.name
      assert_equal 1, $counting_loaded_times
      
      assert_nothing_raised { kls = a }
      assert_equal 1, $counting_loaded_times
    end
  end
  
  def test_removal_from_tree_should_be_detected
    with_loading 'dependencies' do
      root = Dependencies.load_paths.first
      c = ServiceOne
      Dependencies.clear
      assert ! defined?(ServiceOne)
      begin
        Dependencies.load_missing_constant(c, :FakeMissing)
        flunk "Expected exception"
      rescue ArgumentError => e
        assert_match %r{ServiceOne has been removed from the module tree}i, e.message
      end
    end
  end
  
  def test_nested_load_error_isnt_rescued
    with_loading 'dependencies' do
      assert_raises(MissingSourceFile) do
        RequiresNonexistent1
      end
    end
  end
  
  def test_load_once_paths_do_not_add_to_autoloaded_constants
    with_loading 'autoloading_fixtures' do
      Dependencies.load_once_paths = Dependencies.load_paths.dup
      
      assert ! Dependencies.autoloaded?("ModuleFolder")
      assert ! Dependencies.autoloaded?("ModuleFolder::NestedClass")
      assert ! Dependencies.autoloaded?(ModuleFolder)
      
      1 if ModuleFolder::NestedClass # 1 if to avoid warning
      assert ! Dependencies.autoloaded?(ModuleFolder::NestedClass)
    end
  ensure
    Object.send(:remove_const, :ModuleFolder) if defined?(ModuleFolder)
    Dependencies.load_once_paths = []
  end
  
  def test_application_should_special_case_application_controller
    with_loading 'autoloading_fixtures' do
      require_dependency 'application'
      assert_equal 10, ApplicationController
      assert Dependencies.autoloaded?(:ApplicationController)
    end
  end
  
  def test_const_missing_on_kernel_should_fallback_to_object
    with_loading 'autoloading_fixtures' do
      kls = Kernel::E
      assert_equal "E", kls.name
      assert_equal kls.object_id, Kernel::E.object_id
    end
  end
  
  def test_preexisting_constants_are_not_marked_as_autoloaded
    with_loading 'autoloading_fixtures' do
      require_dependency 'e'
      assert Dependencies.autoloaded?(:E)
      Dependencies.clear
    end
    
    Object.const_set :E, Class.new
    with_loading 'autoloading_fixtures' do
      require_dependency 'e'
      assert ! Dependencies.autoloaded?(:E), "E shouldn't be marked autoloaded!"
      Dependencies.clear
    end
    
  ensure
    Object.send :remove_const, :E if Object.const_defined?(:E)
  end
  
end
