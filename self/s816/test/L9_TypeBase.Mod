MODULE L9_TypeBase;
  TYPE
    Base* = RECORD x*: INTEGER END;
    Ext1* = RECORD (Base) y*: INTEGER END;
    PBase* = POINTER TO Base;
    PExt1* = POINTER TO Ext1;
END L9_TypeBase.
