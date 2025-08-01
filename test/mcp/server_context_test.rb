# frozen_string_literal: true

require "test_helper"

module MCP
  class ServerContextTest < ActiveSupport::TestCase
    # Tool without server_context parameter
    class SimpleToolWithoutContext < Tool
      tool_name "simple_without_context"
      description "A tool that doesn't use server_context"
      input_schema({ properties: { message: { type: "string" } }, required: ["message"] })

      class << self
        def call(message:)
          Tool::Response.new([
            { type: "text", content: "SimpleToolWithoutContext: #{message}" },
          ])
        end
      end
    end

    # Tool with optional server_context parameter
    class ToolWithOptionalContext < Tool
      tool_name "tool_with_optional_context"
      description "A tool with optional server_context"
      input_schema({ properties: { message: { type: "string" } }, required: ["message"] })

      class << self
        def call(message:, server_context: nil)
          context_info = server_context ? "with context: #{server_context[:user]}" : "no context"
          Tool::Response.new([
            { type: "text", content: "ToolWithOptionalContext: #{message} (#{context_info})" },
          ])
        end
      end
    end

    # Tool with required server_context parameter
    class ToolWithRequiredContext < Tool
      tool_name "tool_with_required_context"
      description "A tool that requires server_context"
      input_schema({ properties: { message: { type: "string" } }, required: ["message"] })

      class << self
        def call(message:, server_context:)
          Tool::Response.new([
            { type: "text", content: "ToolWithRequiredContext: #{message} for user #{server_context[:user]}" },
          ])
        end
      end
    end

    setup do
      @server_with_context = Server.new(
        name: "test_server",
        tools: [SimpleToolWithoutContext, ToolWithOptionalContext, ToolWithRequiredContext],
        server_context: { user: "test_user" },
      )

      @server_without_context = Server.new(
        name: "test_server_no_context",
        tools: [SimpleToolWithoutContext, ToolWithOptionalContext],
      )
    end

    test "tool without server_context parameter works when server has context" do
      request = {
        jsonrpc: "2.0",
        id: 1,
        method: "tools/call",
        params: {
          name: "simple_without_context",
          arguments: { message: "Hello" },
        },
      }

      response = @server_with_context.handle(request)

      assert response[:result]
      assert_equal "SimpleToolWithoutContext: Hello", response[:result][:content][0][:content]
    end

    test "tool with optional server_context receives context when server has it" do
      request = {
        jsonrpc: "2.0",
        id: 1,
        method: "tools/call",
        params: {
          name: "tool_with_optional_context",
          arguments: { message: "Hello" },
        },
      }

      response = @server_with_context.handle(request)

      assert response[:result]
      assert_equal "ToolWithOptionalContext: Hello (with context: test_user)",
        response[:result][:content][0][:content]
    end

    test "tool with optional server_context works when server has no context" do
      request = {
        jsonrpc: "2.0",
        id: 1,
        method: "tools/call",
        params: {
          name: "tool_with_optional_context",
          arguments: { message: "Hello" },
        },
      }

      response = @server_without_context.handle(request)

      assert response[:result]
      assert_equal "ToolWithOptionalContext: Hello (no context)",
        response[:result][:content][0][:content]
    end

    test "tool with required server_context receives context" do
      request = {
        jsonrpc: "2.0",
        id: 1,
        method: "tools/call",
        params: {
          name: "tool_with_required_context",
          arguments: { message: "Hello" },
        },
      }

      response = @server_with_context.handle(request)

      assert response[:result]
      assert_equal "ToolWithRequiredContext: Hello for user test_user",
        response[:result][:content][0][:content]
    end

    test "tool with required server_context fails when server has no context" do
      server_no_context = Server.new(
        name: "test_server_no_context",
        tools: [ToolWithRequiredContext],
      )

      request = {
        jsonrpc: "2.0",
        id: 1,
        method: "tools/call",
        params: {
          name: "tool_with_required_context",
          arguments: { message: "Hello" },
        },
      }

      response = server_no_context.handle(request)

      assert response[:error]
      # The error is wrapped as "Internal error calling tool..."
      assert_equal "Internal error", response[:error][:message]
    end

    test "call_tool_with_args correctly detects server_context parameter presence" do
      # Tool without server_context
      refute SimpleToolWithoutContext.method(:call).parameters.any? { |_type, name| name == :server_context }

      # Tool with optional server_context
      assert ToolWithOptionalContext.method(:call).parameters.any? { |_type, name| name == :server_context }

      # Tool with required server_context
      assert ToolWithRequiredContext.method(:call).parameters.any? { |_type, name| name == :server_context }
    end

    test "tools can use splat kwargs to accept any arguments including server_context" do
      class FlexibleTool < Tool
        tool_name "flexible_tool"

        class << self
          def call(**kwargs)
            message = kwargs[:message]
            context = kwargs[:server_context]

            Tool::Response.new([
              {
                type: "text",
                content: "FlexibleTool: #{message} (context: #{context ? "present" : "absent"})",
              },
            ])
          end
        end
      end

      server = Server.new(
        name: "test_server",
        tools: [FlexibleTool],
        server_context: { user: "test_user" },
      )

      request = {
        jsonrpc: "2.0",
        id: 1,
        method: "tools/call",
        params: {
          name: "flexible_tool",
          arguments: { message: "Hello" },
        },
      }

      response = server.handle(request)

      assert response[:result]
      assert_equal "FlexibleTool: Hello (context: present)",
        response[:result][:content][0][:content]
    end

    # Prompt tests

    # Prompt without server_context parameter
    class SimplePromptWithoutContext < Prompt
      prompt_name "simple_prompt_without_context"
      description "A prompt that doesn't use server_context"
      arguments [Prompt::Argument.new(name: "message", required: true)]

      class << self
        def template(args)
          Prompt::Result.new(
            messages: [
              Prompt::Message.new(
                role: "user",
                content: Content::Text.new("SimplePromptWithoutContext: #{args[:message]}"),
              ),
            ],
          )
        end
      end
    end

    # Prompt with optional server_context parameter
    class PromptWithOptionalContext < Prompt
      prompt_name "prompt_with_optional_context"
      description "A prompt with optional server_context"
      arguments [Prompt::Argument.new(name: "message", required: true)]

      class << self
        def template(args, server_context: nil)
          context_info = server_context ? "with context: #{server_context[:user]}" : "no context"
          Prompt::Result.new(
            messages: [
              Prompt::Message.new(
                role: "user",
                content: Content::Text.new("PromptWithOptionalContext: #{args[:message]} (#{context_info})"),
              ),
            ],
          )
        end
      end
    end

    # Prompt with required server_context parameter
    class PromptWithRequiredContext < Prompt
      prompt_name "prompt_with_required_context"
      description "A prompt that requires server_context"
      arguments [Prompt::Argument.new(name: "message", required: true)]

      class << self
        def template(args, server_context:)
          Prompt::Result.new(
            messages: [
              Prompt::Message.new(
                role: "user",
                content: Content::Text.new(
                  "PromptWithRequiredContext: #{args[:message]} for user #{server_context[:user]}",
                ),
              ),
            ],
          )
        end
      end
    end

    test "prompt without server_context parameter works when server has context" do
      server = Server.new(
        name: "test_server",
        prompts: [SimplePromptWithoutContext],
        server_context: { user: "test_user" },
      )

      request = {
        jsonrpc: "2.0",
        id: 1,
        method: "prompts/get",
        params: {
          name: "simple_prompt_without_context",
          arguments: { message: "Hello" },
        },
      }

      response = server.handle(request)

      assert response[:result]
      assert_equal "SimplePromptWithoutContext: Hello", response[:result][:messages][0][:content][:text]
    end

    test "prompt with optional server_context receives context when server has it" do
      server = Server.new(
        name: "test_server",
        prompts: [PromptWithOptionalContext],
        server_context: { user: "test_user" },
      )

      request = {
        jsonrpc: "2.0",
        id: 1,
        method: "prompts/get",
        params: {
          name: "prompt_with_optional_context",
          arguments: { message: "Hello" },
        },
      }

      response = server.handle(request)

      assert response[:result]
      assert_equal "PromptWithOptionalContext: Hello (with context: test_user)",
        response[:result][:messages][0][:content][:text]
    end

    test "prompt with optional server_context works when server has no context" do
      server = Server.new(
        name: "test_server",
        prompts: [PromptWithOptionalContext],
      )

      request = {
        jsonrpc: "2.0",
        id: 1,
        method: "prompts/get",
        params: {
          name: "prompt_with_optional_context",
          arguments: { message: "Hello" },
        },
      }

      response = server.handle(request)

      assert response[:result]
      assert_equal "PromptWithOptionalContext: Hello (no context)",
        response[:result][:messages][0][:content][:text]
    end

    test "prompt with required server_context receives context" do
      server = Server.new(
        name: "test_server",
        prompts: [PromptWithRequiredContext],
        server_context: { user: "test_user" },
      )

      request = {
        jsonrpc: "2.0",
        id: 1,
        method: "prompts/get",
        params: {
          name: "prompt_with_required_context",
          arguments: { message: "Hello" },
        },
      }

      response = server.handle(request)

      assert response[:result]
      assert_equal "PromptWithRequiredContext: Hello for user test_user",
        response[:result][:messages][0][:content][:text]
    end

    test "prompts can use splat kwargs to accept any arguments including server_context" do
      class FlexiblePrompt < Prompt
        prompt_name "flexible_prompt"
        arguments [Prompt::Argument.new(name: "message", required: true)]

        class << self
          def template(args, **kwargs)
            message = args[:message]
            context = kwargs[:server_context]

            Prompt::Result.new(
              messages: [
                Prompt::Message.new(
                  role: "user",
                  content: Content::Text.new("FlexiblePrompt: #{message} (context: #{context ? "present" : "absent"})"),
                ),
              ],
            )
          end
        end
      end

      server = Server.new(
        name: "test_server",
        prompts: [FlexiblePrompt],
        server_context: { user: "test_user" },
      )

      request = {
        jsonrpc: "2.0",
        id: 1,
        method: "prompts/get",
        params: {
          name: "flexible_prompt",
          arguments: { message: "Hello" },
        },
      }

      response = server.handle(request)

      assert response[:result]
      assert_equal "FlexiblePrompt: Hello (context: present)",
        response[:result][:messages][0][:content][:text]
    end
  end
end
