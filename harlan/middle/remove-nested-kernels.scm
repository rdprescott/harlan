(library
  (harlan middle remove-nested-kernels)
  (export remove-nested-kernels)
  (import (rnrs) (elegant-weapons helpers)
    (harlan helpers))

;; This pass takes a nest of kernels and turns all but the innermost
;; one into for loops. This isn't the best way to do this, but it's
;; the easiest way to support nested kernels and will give us
;; something to build off of.

(define-match remove-nested-kernels
  ((module ,[Decl -> decl*] ...)
   `(module . ,decl*)))

(define-match Decl
  ((fn ,name ,args ,type ,[(Stmt #f) -> stmt])
   `(fn ,name ,args ,type ,stmt))
  ((extern . ,rest)
   `(extern . ,rest)))

(define (any? ls)
  (and (not (null? ls))
       (or (car ls) (any? (cdr ls)))))

(define (kernel-arg->binding i)
  (lambda (x t xs)
    `(,x ,t (vector-ref ,t ,xs (var int ,i)))))

(define (kernel->for x xt e rest body)
  (match body
    (((vec ,t)
      ,dims
      (((,x* ,t*) (,xs* ,ts*) ,d*) ...))
     (let ((i (gensym 'i)) (expr (gensym 'expr)))
       (assert (= (length dims) 1))
       `(let ((,x ,xt (make-vector ,t ,(car dims))))
          (begin
            (for (,i (int 0) ,(car dims) (int 1))
                 (let ,(map (kernel-arg->binding i) x* t* xs*)
                   ,((remove-global-id-stmt i)
                     ((set-kernel-return t x i) e))))
            ,rest))))
    (,else (error 'kernel->for "unmatched datum" body))))

(define-match (Let finish k)
  (() finish)
  (((,x ,xt (kernel ,body ... ,[(Expr #t) -> e])) . ,[rest])
   (if k
       (kernel->for x xt e rest body)
       `(let ((,x ,xt (kernel ,body ... ,e))) ,rest)))
  (((,x ,t ,e) . ,[rest])
   `(let ((,x ,t ,e)) ,rest)))

(define-match (Stmt k)
  ((let ,b ,[stmt]) ((Let stmt k) b))
  ((begin ,[stmt*] ...) (make-begin stmt*))
  ((error ,x) `(error ,x))
  ((for ,b ,[stmt]) `(for ,b ,stmt))
  ((while ,t ,[stmt]) `(while ,t ,stmt))
  ((if ,test ,[conseq]) `(if ,test ,conseq))
  ((if ,test ,[conseq] ,[alt])
   `(if ,test ,conseq ,alt))
  ((set! ,lhs ,rhs) `(set! ,lhs ,rhs))
  ((do ,e) `(do ,e))
  ((print . ,e*) `(print . ,e*))
  ((assert ,e) `(assert ,e))
  ((return) `(return))
  ((return ,e) `(return ,e)))

(define-match (Expr k)
  ((let ,b ,[expr]) ((Let expr k) b))
  ((begin ,[(Stmt k) -> stmt*] ... ,[e])
   `(begin ,@stmt* ,e))
  (,else else))

(define-match (set-kernel-return t x i)
  ((begin ,stmt* ... ,[expr])
   `(begin ,@stmt* ,expr))
  ((let ,b ,[expr])
   `(let ,b ,expr))
  (,else
   `(set! (vector-ref ,t (var (vec ,t) ,x) (var int ,i))
          ,else)))

(define-match (remove-global-id-stmt i)
  ((let ((,x ,t ,[(remove-global-id-expr i) -> e]) ...)
     ,[stmt])
   `(let ((,x ,t ,e) ...) ,stmt))
  ((begin ,[stmt*] ...)
   `(begin . ,stmt*))
  ((error ,x)
   `(error ,x))
  ((for (,x ,[(remove-global-id-expr i) -> start]
            ,[(remove-global-id-expr i) -> end]
            ,[(remove-global-id-expr i) -> step])
        ,[stmt])
   `(for (,x ,start ,end ,step) ,stmt))
  ((while ,[(remove-global-id-expr i) -> t] ,[stmt])
   `(while ,t ,stmt))
  ((if ,[(remove-global-id-expr i) -> t] ,[c])
   `(if ,t ,c))
  ((if ,[(remove-global-id-expr i) -> t] ,[c] ,[a])
   `(if ,t ,c ,a))
  ((set! ,[(remove-global-id-expr i) -> lhs]
         ,[(remove-global-id-expr i) -> rhs])
   `(set! ,lhs ,rhs))
  ((do ,[(remove-global-id-expr i) -> e])
   `(do ,e))
  ((print ,[(remove-global-id-expr i) -> e*])
   `(print . ,e*))
  ((assert ,[(remove-global-id-expr i) -> e])
   `(assert ,e))
  ((return) `(return))
  ((return ,[(remove-global-id-expr i) -> e])
   `(return ,e)))

(define-match (remove-global-id-expr i)
  ((,t ,x) (guard (scalar-type? t)) `(,t ,x))
  ((var ,t ,x)
   `(var ,t ,x))
  ((begin ,[(remove-global-id-stmt i) -> stmt*] ...
          ,[expr])
   `(begin ,@stmt* ,expr))
  ((let ((,x ,t ,[e]) ...) ,[expr])
   `(let ((,x ,t ,e) ...) ,expr))
  ((if ,[t] ,[c] ,[a])
   `(if ,t ,c ,a))
  ((make-vector ,t ,[n])
   `(make-vector ,t ,n))
  ((call
    (c-expr ((int) -> int) get_global_id)
    ,n)
   `(var int ,i))
  ;; Don't go inside kernels, the get-global-id is out of scope.
  ((kernel ,t (,[dims] ...)
           (((,x ,xt) (,[e] ,et) ,i^) ...)
           ,body)
   `(kernel ,t (,dims ...)
            (((,x ,xt) (,e ,et) ,i^) ...)
            ,body))
  ((call ,[fn] ,[args] ...)
   `(call ,fn . ,args))
  ((int->float ,[t])
   `(int->float ,t))
  ((length ,[t])
   `(length ,t))
  ((c-expr ,t ,x)
   `(c-expr ,t ,x))
  ((vector-ref ,t ,[v] ,[i])
   `(vector-ref ,t ,v ,i))
  ((,op ,[lhs] ,[rhs])
   (guard (or (binop? op) (relop? op)))
   `(,op ,lhs ,rhs)))

;;end library
)
