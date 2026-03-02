module ApplicationHelper
  def render_markdown(text)
    return "" if text.blank?

    renderer = Redcarpet::Render::HTML.new(
      hard_wrap: true,
      link_attributes: { target: "_blank", rel: "noopener noreferrer" }
    )
    markdown = Redcarpet::Markdown.new(renderer,
      autolink: true,
      tables: true,
      fenced_code_blocks: true,
      strikethrough: true,
      highlight: true,
      no_intra_emphasis: true
    )

    sanitize(markdown.render(text), tags: %w[p br h1 h2 h3 h4 ul ol li a strong em code pre blockquote table thead tbody tr th td hr mark],
                                    attributes: %w[href target rel class])
  end
end
