Document = Backbone.Model.extend
  defaults:
    code: ''
    graph: 0

  initialize: () ->
    language = '''
      %lex
      %%

      \\n___\\n      return '___'
      "<"            return '<'
      ">"            return '>'
      "("            return '('
      ")"            return ')'
      "["            return '['
      "]"            return ']'
      [_]            return 'UNDERSCORE'
      (" "|\\t)+     return 'SPACES'
      ";"            return ';'
      [0-9]          return 'DIGIT'
      [a-zA-Z]       return 'ALPHABETIC_ASCII'
      .              return 'OTHER_CHAR'
      \\n            return 'NEWLINE'
      <<EOF>>        return 'EOF'

      /lex

      %start Document
      %%

      Document
        : EOF
        | Code EOF
        | Code '___' Directives EOF
        ;

      Code
        : TChars
        | Span
        | %empty
        | Code Code
        ;

      TChar
        : OTHER_CHAR
        | '('
        | ')'
        | '['
        | ']'
        | ';'
        | UNDERSCORE
        | DIGIT
        | ALPHABETIC_ASCII
        | SPACES
        | NEWLINE
        ;

      TChars
        : TChar
          { yy.on_text($1); }
        | TChars TChar
          { $$ = $1+$2; yy.on_text($2);}
        ;

      Span
        : '<' TChars '>' '(' Id ')'
          { yy.on_annotation($2, $5); }
        ;

      TextWithoutNewlineNorSpaceChar
        : NotNewlineNorSpaceChar
        | TextWithoutNewlineNorSpaceChar NotNewlineNorSpaceChar
          { $$ = $1+$2; }
        ;

      TextWithoutNewline
        : NotNewlineChar
        | TextWithoutNewline NotNewlineChar
          { $$ = $1+$2; }
        ;

      NotNewlineNorSpaceChar
        : OTHER_CHAR
        | '<'
        | '>'
        | '('
        | ')'
        | '['
        | ']'
        | ';'
        | UNDERSCORE
        | DIGIT
        | ALPHABETIC_ASCII
        ;

      NotNewlineChar
        : NotNewlineNorSpaceChar
        | SPACES
        ;

      SpacesOrNothing
        : SPACES
        | %empty
        ;

      SpacesNewlinesOrNothing
        : SPACES
        | %empty
        | SpacesNewlinesOrNothing NEWLINE SpacesNewlinesOrNothing
        ;

      Id
        : IdChar
        | Id IdChar
          { $$ = $1+$2; }
        ;

      IdChar
        : UNDERSCORE
        | DIGIT
        | ALPHABETIC_ASCII
        ;

      Directives
        : Directive
        | Directive NEWLINE Directives
        ;

      Directive
        : SpacesOrNothing '(' Id ')' SpacesOrNothing POSequence SpacesOrNothing
          { yy.on_directive($6, $3); }
        | SpacesOrNothing '[' Id ']' SpacesOrNothing POSequence SpacesOrNothing
          { yy.on_directive($6, $3); }
        | SpacesOrNothing
        ;

      /* RDF */
      POSequence
        : POPair
          { $$ = [$1]; }
        | POSequence SpacesOrNothing ';' SpacesOrNothing POPair
          { $$ = $1.concat([$5]); }
        ;

      POPair
        : Predicate SPACES Object
          { $$ = {predicate: $1, object: $3}; }
        ;

      POChar
        : OTHER_CHAR
        | '<'
        | '>'
        | '('
        | ')'
        | '['
        | ']'
        | UNDERSCORE
        | DIGIT
        | ALPHABETIC_ASCII
        ;

      POChars
        : POChar
        | POChar POChars
          { $$ = $1+$2; }
        ;

      Predicate
        : POChars
        ;

      Object
        : POChars
        ;

      '''

    # generate the parser on the fly
    Jison.print = () ->
    @_jison_parser = Jison.Generator(bnf.parse(language), {type: 'lalr'}).createParser()

    # custom error handling: trigger an 'error' event
    @_jison_parser.yy.parseError = (message, details) =>
       @trigger('parse_error', message, details)

    # update the parser's status whenever a language item is encountered
    @_jison_parser.yy.on_text = (content) =>
      @offset += content.length
      @plain_text += content

    @_jison_parser.yy.on_annotation = (content, id) =>
      @annotations.push {
        id: id,
        start: @offset - content.length,
        end: @offset,
        content: content
      }

    @_jison_parser.yy.on_directive = (popairs, id) =>
      @directives.push {
        id: id,
        popairs: popairs
      }

  update: (code) ->
    @set
      code: code

    # parse the code
    @offset = 0
    @annotations = []
    @directives = []
    @plain_text = ''

    try
      @_jison_parser.parse(code)

      # resolve annotations-directive reference
      @annotations.forEach (a) =>
        a.directives = []
        @directives.forEach (d) =>
          if a.id is d.id
            a.directives.push d

      # update the graph
      @set
        graph: 1
    catch error
      console.debug error