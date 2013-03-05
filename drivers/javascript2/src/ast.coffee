goog.provide("rethinkdb.ast")

goog.require("rethinkdb.base")
goog.require("rethinkdb.errors")
goog.require("Term2")
goog.require("Datum")

class TermBase
    constructor: ->
        self = ((field) -> self.getAttr(field))
        self.__proto__ = @.__proto__
        return self

    run: (conn, cb) ->
        conn._start @, cb

    toString: -> RqlQueryPrinter::printQuery(@)

class RDBVal extends TermBase
    eq: (others...) -> new Eq {}, @, others...
    ne: (others...) -> new Ne {}, @, others...
    lt: (others...) -> new Lt {}, @, others...
    le: (others...) -> new Le {}, @, others...
    gt: (others...) -> new Gt {}, @, others...
    ge: (others...) -> new Ge {}, @, others...

    not: -> new Not {}, @

    add: (others...) -> new Add {}, @, others...
    sub: (others...) -> new Sub {}, @, others...
    mul: (others...) -> new Mul {}, @, others...
    div: (others...) -> new Div {}, @, others...
    mod: (other) -> new Mod {}, @, other

    append: ar (val) -> new Append {}, @, val
    slice: (left=0, right=-1) -> new Slice {}, @, left, right
    skip: ar (index) -> new Skip {}, @, index
    limit: ar (index) -> new Limit {}, @, index
    getAttr: ar (field) -> new GetAttr {}, @, field
    contains: (fields...) -> new Contains {}, @, fields...
    pluck: (fields...) -> new Pluck {}, @, fields...
    without: (fields...) -> new Without {}, @, fields...
    merge: ar (other) -> new Merge {}, @, other
    between: ar (left, right) -> new Between {left_bound:left, right_bound:right}, @
    reduce: (func, base) -> new Reduce {base:base}, @, funcWrap(func)
    map: ar (func) -> new Map {}, @, funcWrap(func)
    filter: ar (predicate) -> new Filter {}, @, funcWrap(predicate)
    concatMap: ar (func) -> new ConcatMap {}, @, funcWrap(func)
    orderBy: (fields...) -> new OrderBy {}, @, fields...
    distinct: -> new Distinct {}, @
    count: -> new Count {}, @
    union: (others...) -> new Union {}, @, others...
    nth: ar (index) -> new Nth {}, @, index
    groupedMapReduce: ar (group, map, reduce) -> new GroupedMapReduce {}, @, group, map, reduce
    groupBy: (attrs..., collector) -> new GroupBy {}, @, attrs, collector
    innerJoin: ar (other, predicate) -> new InnerJoin {}, @, other, predicate
    outerJoin: ar (other, predicate) -> new OuterJoin {}, @, other, predicate
    eqJoin: ar (left_attr, right) -> new EqJoin {}, @, left_attr, right
    zip: -> new Zip {}, @
    coerce: ar (type) -> new Coerce {}, @, type
    typeOf: -> new TypeOf {}, @
    update: ar (func) -> new Update {}, @, funcWrap(func)
    delete: -> new Delete {}, @
    replace: ar (func) -> new Replace {}, @, funcWrap(func)
    do: ar (func) -> new FunCall {}, funcWrap(func), @

    or: (others...) -> new Any {}, @, others...
    and: (others...) -> new All {}, @, others...

    forEach: ar (func) -> new ForEach {}, @, func

class DatumTerm extends RDBVal
    args: []
    optargs: {}

    constructor: (val) ->
        self = super()
        self.data = val
        return self

    compose: ->
        switch typeof @data
            when 'string'
                '"'+@data+'"'
            else
                ''+@data

    build: ->
        datum = new Datum
        if @data is null
            datum.setType Datum.DatumType.R_NULL
        else
            switch typeof @data
                when 'number'
                    datum.setType Datum.DatumType.R_NUM
                    datum.setRNum @data
                when 'boolean'
                    datum.setType Datum.DatumType.R_BOOL
                    datum.setRBool @data
                when 'string'
                    datum.setType Datum.DatumType.R_STR
                    datum.setRStr @data
                else
                    throw new RqlDriverError "Unknown datum value \"#{@data}\", did you forget a \"return\"?"
        term = new Term2
        term.setType Term2.TermType.DATUM
        term.setDatum datum
        return term

    @deconstruct: (datum) ->
        switch datum.getType()
            when Datum.DatumType.R_NULL
                null
            when Datum.DatumType.R_BOOL
                datum.getRBool()
            when Datum.DatumType.R_NUM
                datum.getRNum()
            when Datum.DatumType.R_STR
                datum.getRStr()
            when Datum.DatumType.R_ARRAY
                DatumTerm.deconstruct dt for dt in datum.rArrayArray()
            when Datum.DatumType.R_OBJECT
                obj = {}
                for pair in datum.rObjectArray()
                    obj[pair.getKey()] = DatumTerm.deconstruct pair.getVal()
                obj

class RDBOp extends RDBVal
    constructor: (optargs, args...) ->
        self = super()
        self.args = (rethinkdb.expr arg for arg in args)
        self.optargs = {}
        for own key,val of optargs
            if val is undefined then continue
            self.optargs[key] = rethinkdb.expr val
        return self

    build: ->
        term = new Term2
        term.setType @tt
        for arg in @args
            term.addArgs arg.build()
        for own key,val of @optargs
            pair = new Term2.AssocPair
            pair.setKey key
            pair.setVal val.build()
            term.addOptargs pair
        return term

    compose: (args, optargs) ->
        if @st
            return ['r.', @st, '(', intspallargs(args, optargs), ')']
        else
            if @args[0] instanceof DatumTerm
                args[0] = ['r(', args[0], ')']
            return [args[0], '.', @mt, '(', intspallargs(args[1..], optargs), ')']

intsp = (seq) ->
    unless seq[0]? then return []
    res = [seq[0]]
    for e in seq[1..]
        res.push(', ', e)
    return res

kved = (optargs) ->
    ['{', intsp([k, ': ', v] for own k,v of optargs), '}']

intspallargs = (args, optargs) ->
    argrepr = []
    if args.length > 0
        argrepr.push(intsp(args))
    if Object.keys(optargs).length > 0
        if argrepr.length > 0
            argrepr.push(', ')
        argrepr.push(kved(optargs))
    return argrepr

class MakeArray extends RDBOp
    tt: Term2.TermType.MAKE_ARRAY
    compose: (args) -> ['[', intsp(args), ']']
        

class MakeObject extends RDBOp
    tt: Term2.TermType.MAKE_OBJ
    compose: (args, optargs) -> kved(optargs)

class Var extends RDBOp
    tt: Term2.TermType.VAR
    compose: (args) -> ['var_'+args[0]]

class JavaScript extends RDBOp
    tt: Term2.TermType.JAVASCRIPT
    st: 'js'

class UserError extends RDBOp
    tt: Term2.TermType.ERROR
    st: 'error'

class ImplicitVar extends RDBOp
    tt: Term2.TermType.IMPLICIT_VAR
    compose: -> ['r.row']

class Db extends RDBOp
    tt: Term2.TermType.DB
    st: 'db'

    tableCreate: aropt (tblName, opts) -> new TableCreate opts, @, tblName
    tableDrop: ar (tblName) -> new TableDrop {}, @, tblName
    tableList: ar(-> new TableList {}, @)

    table: (tblName, opts) -> new Table opts, @, tblName

class Table extends RDBOp
    tt: Term2.TermType.TABLE

    get: aropt (key, opts) -> new Get opts, @, key
    insert: aropt (doc, opts) -> new Insert opts, @, doc

    compose: (args, optargs) ->
        if @args[0] instanceof Db
            [args[0], '.table(', args[1], ')']
        else
            ['r.table(', args[0], ')']

class Get extends RDBOp
    tt: Term2.TermType.GET
    mt: 'get'

class Eq extends RDBOp
    tt: Term2.TermType.EQ
    mt: 'eq'

class Ne extends RDBOp
    tt: Term2.TermType.NE
    mt: 'ne'

class Lt extends RDBOp
    tt: Term2.TermType.LT
    mt: 'lt'

class Le extends RDBOp
    tt: Term2.TermType.LE
    mt: 'le'

class Gt extends RDBOp
    tt: Term2.TermType.GT
    mt: 'gt'

class Ge extends RDBOp
    tt: Term2.TermType.GE
    mt: 'ge'

class Not extends RDBOp
    tt: Term2.TermType.NOT
    mt: 'not'

class Add extends RDBOp
    tt: Term2.TermType.ADD
    mt: 'add'

class Sub extends RDBOp
    tt: Term2.TermType.SUB
    mt: 'sub'

class Mul extends RDBOp
    tt: Term2.TermType.MUL
    mt: 'mul'

class Div extends RDBOp
    tt: Term2.TermType.DIV
    mt: 'div'

class Mod extends RDBOp
    tt: Term2.TermType.MOD
    mt: 'mod'

class Append extends RDBOp
    tt: Term2.TermType.APPEND
    mt: 'append'

class Slice extends RDBOp
    tt: Term2.TermType.SLICE
    st: 'slice'

class Skip extends RDBOp
    tt: Term2.TermType.SKIP
    mt: 'skip'

class Limit extends RDBOp
    tt: Term2.TermType.LIMIT
    st: 'limit'

class GetAttr extends RDBOp
    tt: Term2.TermType.GETATTR
    compose: (args) -> [args[0], '(', args[1], ')']

class Contains extends RDBOp
    tt: Term2.TermType.CONTAINS
    mt: 'contains'

class Pluck extends RDBOp
    tt: Term2.TermType.PLUCK
    mt: 'pluck'

class Without extends RDBOp
    tt: Term2.TermType.WITHOUT
    mt: 'without'

class Merge extends RDBOp
    tt: Term2.TermType.MERGE
    mt: 'merge'

class Between extends RDBOp
    tt: Term2.TermType.BETWEEN
    mt: 'between'

class Reduce extends RDBOp
    tt: Term2.TermType.REDUCE
    mt: 'reduce'

class Map extends RDBOp
    tt: Term2.TermType.MAP
    mt: 'map'

class Filter extends RDBOp
    tt: Term2.TermType.FILTER
    mt: 'filter'

class ConcatMap extends RDBOp
    tt: Term2.TermType.CONCATMAP
    mt: 'concatMap'

class OrderBy extends RDBOp
    tt: Term2.TermType.ORDERBY
    mt: 'orderBy'

class Distinct extends RDBOp
    tt: Term2.TermType.DISTINCT
    mt: 'distinct'

class Count extends RDBOp
    tt: Term2.TermType.COUNT
    mt: 'count'

class Union extends RDBOp
    tt: Term2.TermType.UNION
    mt: 'union'

class Nth extends RDBOp
    tt: Term2.TermType.NTH
    mt: 'nth'

class GroupedMapReduce extends RDBOp
    tt: Term2.TermType.GROUPED_MAP_REDUCE
    mt: 'groupedMapReduce'

class GroupBy extends RDBOp
    tt: Term2.TermType.GROUPBY
    mt: 'groupBy'

class GroupBy extends RDBOp
    tt: Term2.TermType.GROUPBY
    mt: 'groupBy'

class InnerJoin extends RDBOp
    tt: Term2.TermType.INNER_JOIN
    mt: 'innerJoin'

class OuterJoin extends RDBOp
    tt: Term2.TermType.OUTER_JOIN
    mt: 'outerJoin'

class EqJoin extends RDBOp
    tt: Term2.TermType.EQ_JOIN
    mt: 'eqJoin'

class Zip extends RDBOp
    tt: Term2.TermType.ZIP
    mt: 'zip'

class Coerce extends RDBOp
    tt: Term2.TermType.COERCE
    mt: 'coerce'

class TypeOf extends RDBOp
    tt: Term2.TermType.TYPEOF
    mt: 'typeOf'

class Update extends RDBOp
    tt: Term2.TermType.UPDATE
    mt: 'update'

class Delete extends RDBOp
    tt: Term2.TermType.DELETE
    mt: 'delete'

class Replace extends RDBOp
    tt: Term2.TermType.REPLACE
    mt: 'replace'

class Insert extends RDBOp
    tt: Term2.TermType.INSERT
    mt: 'insert'

class DbCreate extends RDBOp
    tt: Term2.TermType.DB_CREATE
    st: 'dbCreate'

class DbDrop extends RDBOp
    tt: Term2.TermType.DB_DROP
    st: 'dbDrop'

class DbList extends RDBOp
    tt: Term2.TermType.DB_LIST
    st: 'dbList'

class TableCreate extends RDBOp
    tt: Term2.TermType.TABLE_CREATE
    mt: 'tableCreate'

class TableDrop extends RDBOp
    tt: Term2.TermType.TABLE_DROP
    mt: 'tableDrop'

class TableList extends RDBOp
    tt: Term2.TermType.TABLE_LIST
    mt: 'tableList'

class FunCall extends RDBOp
    tt: Term2.TermType.FUNCALL
    compose: (args) ->
        if args.length > 2
            ['r.do(', intsp(args[1..]), ', ', args[0], ')']
        else
            if @args[1] instanceof DatumTerm
                args[1] = ['r(', args[1], ')']
            [args[1], '.do(', args[0], ')']

class Branch extends RDBOp
    tt: Term2.TermType.BRANCH
    st: 'branch'

class Any extends RDBOp
    tt: Term2.TermType.ANY
    mt: 'or'

class All extends RDBOp
    tt: Term2.TermType.ALL
    mt: 'and'

class ForEach extends RDBOp
    tt: Term2.TermType.FOREACH
    mt: 'forEach'

funcWrap = (val) ->
    if val instanceof Function
        return new Func {}, val

    ivarScan = (node) ->
        unless node instanceof TermBase then return false
        if node instanceof ImplicitVar then return true
        if (node.args.map ivarScan).some((a)->a) then return true
        return false

    if ivarScan(val)
        return new Func {}, (x) -> val

    return val


class Func extends RDBOp
    tt: Term2.TermType.FUNC

    constructor: (optargs, func) ->
        args = []
        argNums = []
        i = 0
        while i < func.length
            argNums.push i
            args.push new Var {}, i
            i++
        body = func(args...)
        argsArr = new MakeArray({}, argNums...)
        return super(optargs, argsArr, body)

    compose: (args) ->
        ['function(', (Var::compose(arg) for arg in args[0][1...-1]), ') { return ', args[1], '; }']
