module.exports = ['unicode', (unicode) ->
  _normalize = (e) ->
    if typeof e is 'string'
      normed = unicode.normalize(e)
      return unicode.fold(normed)
    else
      e

  _matches = (filter, value, match) ->
    matches = true

    for term in filter.terms
      unless match term, value
        matches = false
        if filter.operator is 'and'
          break
      else
        matches = true
        if filter.operator is 'or'
          break
    matches

  _arrayMatches = (filter, value, match) ->
    matches = true
    # Make copy for filtering
    copy = filter.terms.slice()

    copy = copy.filter (e) ->
      match value, e

    if (filter.operator is 'and' and copy.length < filter.terms.length) or
    (filter.operator is 'or' and not copy.length)
      matches = false
    matches

  _checkMatch = (filter, annotation, checker) ->
    autofalsefn = checker.autofalse
    return false if autofalsefn? and autofalsefn annotation

    value = checker.value annotation
    if angular.isArray value
      value = value.map (e) -> e.toLowerCase()
      value = value.map (e) => _normalize(e)
      return _arrayMatches filter, value, checker.match
    else
      value = value.toLowerCase()
      value = _normalize(value)
      return _matches filter, value, checker.match

  # The field configuration
  #
  # [facet_name]:
  #   autofalse: a function for a preliminary false match result
  #   value: a function to extract to facet value for the annotation.
  #   match: a function to check if the extracted value matches the facet value
  fields:
    quote:
      autofalse: (annotation) -> return annotation.references?
      value: (annotation) ->
        quotes = for t in (annotation.target or [])
          for s in (t.selector or []) when s.type is 'TextQuoteSelector'
            unless s.exact then continue
            s.exact
        quotes = Array::concat quotes...
        quotes.join('\n')
      match: (term, value) -> return value.indexOf(term) > -1
    since:
      autofalse: (annotation) -> return not annotation.updated?
      value: (annotation) -> return annotation.updated
      match: (term, value) ->
        delta = Math.round((+new Date - new Date(value)) / 1000)
        return delta <= term
    tag:
      autofalse: (annotation) -> return not annotation.tags?
      value: (annotation) -> return annotation.tags
      match: (term, value) -> return value in term
    text:
      autofalse: (annotation) -> return not annotation.text?
      value: (annotation) -> return annotation.text
      match: (term, value) -> return value.indexOf(term) > -1
    uri:
      autofalse: (annotation) -> return not annotation.uri?
      value: (annotation) -> return annotation.uri
      match: (term, value) -> return value.indexOf(term) > -1
    user:
      autofalse: (annotation) -> return not annotation.user?
      value: (annotation) -> return annotation.user
      match: (term, value) -> return value.indexOf(term) > -1
    type:
      autofalse: (annotation) -> return not annotation.type_id?
      value: (annotation) -> return annotation.type_id + ''
      match: (term, value) -> return value == term
    any:
      fields: ['quote', 'text', 'tag', 'user']

  # Filters a set of annotations, according to a given query.
  #
  # Inputs:
  #   annotations is the input list of annotations (array)
  #   filters is the query is a faceted filter generated by `searchFilter`.
  #
  # It'll handle the annotation matching by the returned field configuration.
  #
  # Returns Array of the matched annotation ids.
  filter: (annotations, filters) ->
    limit = Math.min((filters.result?.terms or [])...)
    count = 0

    # Normalizing the filters, need to do only once.
    for _, filter of filters
      if filter.terms
        console.log("FILTER TERMS BEFORE", filter.terms)
        filter.terms = filter.terms.map (e) =>
          e = e.toLowerCase()
          e = _normalize e
          e
        console.log("FILTER TERMS", filter.terms)

    for annotation in annotations
      break if count >= limit

      match = true
      for category, filter of filters
        break unless match
        continue unless filter.terms.length

        switch category
          when 'any'
            categoryMatch = false
            for field in @fields.any.fields
              for term in filter.terms
                termFilter = {terms: [term], operator: "and"}
                if _checkMatch(termFilter, annotation, @fields[field])
                  categoryMatch = true
                  break
            match = categoryMatch
          else
            match = _checkMatch filter, annotation, @fields[category]

      continue unless match
      count++
      annotation.id
]
