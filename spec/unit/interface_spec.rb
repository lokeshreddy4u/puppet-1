require 'spec_helper'
require 'puppet/face'
require 'puppet/interface'

describe Puppet::Interface do
  subject { Puppet::Interface }

  before :all do
    @faces = Puppet::Interface::FaceCollection.instance_variable_get("@faces").dup
  end

  before :each do
    Puppet::Interface::FaceCollection.instance_variable_get("@faces").clear
  end

  after :all do
    Puppet::Interface::FaceCollection.instance_variable_set("@faces", @faces)
  end

  describe "#[]" do
    it "should fail when no version is requested" do
      expect { subject[:huzzah] }.should raise_error ArgumentError
    end

    it "should raise an exception when the requested version is unavailable" do
      expect { subject[:huzzah, '17.0.0'] }.should raise_error, Puppet::Error
    end

    it "should raise an exception when the requested face doesn't exist" do
      expect { subject[:burrble_toot, :current] }.should raise_error, Puppet::Error
    end
  end

  describe "#define" do
    it "should register the face" do
      face = subject.define(:face_test_register, '0.0.1')
      face.should == subject[:face_test_register, '0.0.1']
    end

    it "should load actions" do
      subject.any_instance.expects(:load_actions)
      subject.define(:face_test_load_actions, '0.0.1')
    end

    it "should require a version number" do
      expect { subject.define(:no_version) }.to raise_error ArgumentError
    end

    it "should support summary builder and accessor methods" do
      subject.new(:foo, '1.0.0').should respond_to(:summary).with(0).arguments
      subject.new(:foo, '1.0.0').should respond_to(:summary=).with(1).arguments
    end

    it "should set the summary text" do
      text = "hello, freddy, my little pal"
      subject.define(:face_test_summary, '1.0.0') do
        summary text
      end
      subject[:face_test_summary, '1.0.0'].summary.should == text
    end

    it "should support mutating the summary" do
      text = "hello, freddy, my little pal"
      subject.define(:face_test_summary, '1.0.0') do
        summary text
      end
      subject[:face_test_summary, '1.0.0'].summary.should == text
      subject[:face_test_summary, '1.0.0'].summary = text + text
      subject[:face_test_summary, '1.0.0'].summary.should == text + text
    end
  end

  describe "#initialize" do
    it "should require a version number" do
      expect { subject.new(:no_version) }.to raise_error ArgumentError
    end

    it "should require a valid version number" do
      expect { subject.new(:bad_version, 'Rasins') }.
        should raise_error ArgumentError
    end

    it "should instance-eval any provided block" do
      face = subject.new(:face_test_block, '0.0.1') do
        action(:something) do
          when_invoked { "foo" }
        end
      end

      face.something.should == "foo"
    end
  end

  it "should have a name" do
    subject.new(:me, '0.0.1').name.should == :me
  end

  it "should stringify with its own name" do
    subject.new(:me, '0.0.1').to_s.should =~ /\bme\b/
  end

  it "should allow overriding of the default format" do
    face = subject.new(:me, '0.0.1')
    face.set_default_format :foo
    face.default_format.should == :foo
  end

  it "should default to :pson for its format" do
    subject.new(:me, '0.0.1').default_format.should == :pson
  end

  # Why?
  it "should create a class-level autoloader" do
    subject.autoloader.should be_instance_of(Puppet::Util::Autoload)
  end

  it "should try to require faces that are not known" do
    pending "mocking require causes random stack overflow"
    subject::FaceCollection.expects(:require).with "puppet/face/foo"
    subject[:foo, '0.0.1']
  end

  it "should be able to load all actions in all search paths"


  it_should_behave_like "things that declare options" do
    def add_options_to(&block)
      subject.new(:with_options, '0.0.1', &block)
    end
  end

  describe "with face-level options" do
    it "should not return any action-level options" do
      face = subject.new(:with_options, '0.0.1') do
        option "--foo"
        option "--bar"
        action :baz do
          option "--quux"
        end
      end
      face.options.should =~ [:foo, :bar]
    end

    it "should fail when a face option duplicates an action option" do
      expect {
        subject.new(:action_level_options, '0.0.1') do
          action :bar do option "--foo" end
          option "--foo"
        end
      }.should raise_error ArgumentError, /Option foo conflicts with existing option foo on/i
    end

    it "should work when two actions have the same option" do
      face = subject.new(:with_options, '0.0.1') do
        action :foo do option "--quux" end
        action :bar do option "--quux" end
      end

      face.get_action(:foo).options.should =~ [:quux]
      face.get_action(:bar).options.should =~ [:quux]
    end
  end

  describe "with inherited options" do
    let :parent do
      parent = Class.new(subject)
      parent.option("--inherited")
      parent.action(:parent_action) do end
      parent
    end

    let :face do
      face = parent.new(:example, '0.2.1')
      face.option("--local")
      face.action(:face_action) do end
      face
    end

    describe "#options" do
      it "should list inherited options" do
        face.options.should =~ [:inherited, :local]
      end

      it "should see all options on face actions" do
        face.get_action(:face_action).options.should =~ [:inherited, :local]
      end

      it "should see all options on inherited actions accessed on the subclass" do
        face.get_action(:parent_action).options.should =~ [:inherited, :local]
      end

      it "should not see subclass actions on the parent class" do
        parent.options.should =~ [:inherited]
      end

      it "should not see subclass actions on actions accessed on the parent class" do
        parent.get_action(:parent_action).options.should =~ [:inherited]
      end
    end

    describe "#get_option" do
      it "should return an inherited option object" do
        face.get_option(:inherited).should be_an_instance_of subject::Option
      end
    end
  end
end
