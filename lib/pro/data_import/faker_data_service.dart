import 'dart:math';

/// Multi-language faker data generation service
/// Provides realistic fake data based on column semantics and locale
class FakerDataService {
  final String locale;
  final Random _random = Random();

  // Locale-specific data pools
  late final FakerLocaleData _localeData;

  FakerDataService({this.locale = 'en'}) {
    _localeData = _loadLocaleData(locale);
  }

  /// Generate a value based on column name and type
  dynamic generateValue({
    required String columnName,
    required String columnType,
    int? rowIndex,
    String? locale,
  }) {
    final semanticType = _detectSemanticType(columnName);
    final effectiveLocale = locale ?? this.locale;

    // Use locale-specific data if available, fallback to English
    final data = effectiveLocale != 'en' && _localeData.isEmpty
        ? _loadLocaleData('en')
        : _localeData;

    switch (semanticType) {
      case SemanticType.name:
        return _generateName(data);
      case SemanticType.email:
        return _generateEmail(data);
      case SemanticType.phone:
        return _generatePhone(effectiveLocale);
      case SemanticType.address:
        return _generateAddress(data);
      case SemanticType.company:
        return _generateCompany(data);
      case SemanticType.product:
        return _generateProduct(data);
      case SemanticType.orderNumber:
        return _generateOrderNumber(rowIndex);
      case SemanticType.uuid:
        return _generateUuid();
      case SemanticType.id:
        return rowIndex ?? _random.nextInt(100000);
      case SemanticType.age:
        return 18 + _random.nextInt(63);
      case SemanticType.price:
        return (_random.nextDouble() * 1000).toStringAsFixed(2);
      case SemanticType.score:
        return _random.nextInt(101);
      case SemanticType.date:
        return _generateDate();
      case SemanticType.boolean:
        return _random.nextBool();
      case SemanticType.text:
        return _generateLoremText(data);
      case SemanticType.url:
        return _generateUrl(data);
      case SemanticType.ipAddress:
        return _generateIpAddress();
      case SemanticType.color:
        return _generateColor();
      default:
        return _generateDefaultValue(columnType, rowIndex);
    }
  }

  /// Detect semantic type from column name
  SemanticType _detectSemanticType(String columnName) {
    final lower = columnName.toLowerCase();

    // Name patterns
    if (_matchesAny(lower, [
      'name',
      '姓名',
      'full_name',
      'first_name',
      'last_name',
      'username',
      'user_name',
      'display_name',
      '昵称',
    ])) {
      return SemanticType.name;
    }

    // Email patterns
    if (_matchesAny(lower, ['email', '邮箱', 'e_mail', 'mail', '电子邮件'])) {
      return SemanticType.email;
    }

    // Phone patterns
    if (_matchesAny(lower, [
      'phone',
      '电话',
      'mobile',
      'tel',
      'telephone',
      'cell',
      '手机号',
      '联系方式',
    ])) {
      return SemanticType.phone;
    }

    // Address patterns
    if (_matchesAny(lower, [
      'address',
      '地址',
      'addr',
      'location',
      'city',
      'country',
      'street',
      'province',
      'state',
      'zip',
      'postal',
    ])) {
      return SemanticType.address;
    }

    // Company patterns
    if (_matchesAny(lower, [
      'company',
      '公司',
      'organization',
      'org',
      'enterprise',
      'business',
      'firm',
    ])) {
      return SemanticType.company;
    }

    // Product patterns
    if (_matchesAny(lower, [
      'product',
      '商品',
      'item',
      'goods',
      'merchandise',
      'sku',
      'commodity',
    ])) {
      return SemanticType.product;
    }

    // Order patterns
    if (_matchesAny(lower, [
      'order',
      '订单',
      'order_no',
      'order_id',
      'order_number',
      'po_number',
      'purchase_order',
    ])) {
      return SemanticType.orderNumber;
    }

    // UUID patterns
    if (_matchesAny(lower, ['uuid', 'guid', 'unique_id'])) {
      return SemanticType.uuid;
    }

    // ID patterns (but not foreign keys)
    if (_matchesAny(lower, ['id', '编号', 'code', 'no', 'number', 'serial']) &&
        !lower.contains('_id')) {
      return SemanticType.id;
    }

    // Age patterns
    if (_matchesAny(lower, ['age', '年龄', 'years'])) {
      return SemanticType.age;
    }

    // Price patterns
    if (_matchesAny(lower, [
      'price',
      '金额',
      'amount',
      'cost',
      'fee',
      'salary',
      'wage',
      'revenue',
      'total',
      'subtotal',
    ])) {
      return SemanticType.price;
    }

    // Score patterns
    if (_matchesAny(lower, [
      'score',
      '分数',
      'grade',
      'rating',
      'mark',
      'points',
      'rank',
      'level',
    ])) {
      return SemanticType.score;
    }

    // Date patterns
    if (_matchesAny(lower, [
      'date',
      '时间',
      'time',
      'created',
      'updated',
      'modified',
      'timestamp',
      'datetime',
      'birthday',
      'deadline',
    ])) {
      return SemanticType.date;
    }

    // Boolean patterns
    if (_matchesAny(lower, [
      'is_',
      'has_',
      'can_',
      'enable',
      'status',
      'active',
      'visible',
      'deleted',
      'flag',
      '是否',
    ])) {
      return SemanticType.boolean;
    }

    // URL patterns
    if (_matchesAny(lower, [
      'url',
      'link',
      'href',
      'website',
      'site',
      'domain',
      'avatar',
      'image',
      'photo',
      'picture',
      'icon',
    ])) {
      return SemanticType.url;
    }

    // IP patterns
    if (_matchesAny(lower, ['ip', 'ip_address', 'host'])) {
      return SemanticType.ipAddress;
    }

    // Color patterns
    if (_matchesAny(lower, [
      'color',
      'colour',
      'bg',
      'background',
      'foreground',
    ])) {
      return SemanticType.color;
    }

    // Text/Description patterns
    if (_matchesAny(lower, [
      'desc',
      'description',
      '备注',
      'comment',
      'note',
      'summary',
      'detail',
      'content',
      'text',
      'message',
      'bio',
      'about',
      'title',
      'subject',
      'topic',
    ])) {
      return SemanticType.text;
    }

    return SemanticType.unknown;
  }

  bool _matchesAny(String text, List<String> patterns) {
    return patterns.any((p) => text.contains(p));
  }

  // Generation methods

  String _generateName(FakerLocaleData data) {
    if (data.firstNames.isNotEmpty && data.lastNames.isNotEmpty) {
      final first = data.firstNames[_random.nextInt(data.firstNames.length)];
      final last = data.lastNames[_random.nextInt(data.lastNames.length)];
      return '$first $last';
    }
    return 'User${_random.nextInt(10000)}';
  }

  String _generateEmail(FakerLocaleData data) {
    final name = _generateName(data).toLowerCase().replaceAll(' ', '.');
    final domains = [
      'gmail.com',
      'yahoo.com',
      'outlook.com',
      'example.com',
      'company.com',
    ];
    return '$name@${domains[_random.nextInt(domains.length)]}';
  }

  String _generatePhone(String locale) {
    switch (locale) {
      case 'zh':
        final prefixes = [
          '138',
          '139',
          '137',
          '136',
          '135',
          '134',
          '150',
          '151',
          '152',
          '157',
          '158',
          '159',
          '182',
          '183',
          '187',
          '188',
        ];
        final prefix = prefixes[_random.nextInt(prefixes.length)];
        final suffix = _random.nextInt(100000000).toString().padLeft(8, '0');
        return '$prefix$suffix';
      case 'de':
        return '+49 ${_random.nextInt(900) + 100} ${_random.nextInt(9000000) + 1000000}';
      case 'fr':
        return '+33 ${_random.nextInt(9) + 1} ${_random.nextInt(90) + 10} ${_random.nextInt(90) + 10} ${_random.nextInt(90) + 10} ${_random.nextInt(90) + 10}';
      case 'ru':
        return '+7 (${_random.nextInt(900) + 100}) ${_random.nextInt(900) + 100}-${_random.nextInt(90) + 10}-${_random.nextInt(90) + 10}';
      default:
        return '(${_random.nextInt(800) + 200}) ${_random.nextInt(900) + 100}-${_random.nextInt(9000) + 1000}';
    }
  }

  String _generateAddress(FakerLocaleData data) {
    if (data.cities.isNotEmpty && data.streets.isNotEmpty) {
      final street = data.streets[_random.nextInt(data.streets.length)];
      final city = data.cities[_random.nextInt(data.cities.length)];
      final number = _random.nextInt(999) + 1;
      return '$number $street, $city';
    }
    return '${_random.nextInt(999) + 1} Main St, City${_random.nextInt(100)}';
  }

  String _generateCompany(FakerLocaleData data) {
    if (data.companies.isNotEmpty) {
      return data.companies[_random.nextInt(data.companies.length)];
    }
    final suffixes = ['Inc', 'Corp', 'Ltd', 'LLC', 'Group', 'Tech'];
    return 'Company${_random.nextInt(1000)} ${suffixes[_random.nextInt(suffixes.length)]}';
  }

  String _generateProduct(FakerLocaleData data) {
    if (data.products.isNotEmpty) {
      return data.products[_random.nextInt(data.products.length)];
    }
    final adjectives = [
      'Premium',
      'Deluxe',
      'Standard',
      'Basic',
      'Advanced',
      'Pro',
    ];
    final nouns = ['Widget', 'Gadget', 'Device', 'Tool', 'Kit', 'System'];
    return '${adjectives[_random.nextInt(adjectives.length)]} ${nouns[_random.nextInt(nouns.length)]} ${_random.nextInt(1000)}';
  }

  String _generateOrderNumber(int? rowIndex) {
    final timestamp = DateTime.now().millisecondsSinceEpoch % 1000000;
    final random = _random.nextInt(1000);
    final index = rowIndex ?? random;
    return 'ORD-${timestamp.toString().padLeft(6, '0')}-${index.toString().padLeft(4, '0')}';
  }

  String _generateUuid() {
    final hex = '0123456789abcdef';
    String segment(int len) =>
        List.generate(len, (_) => hex[_random.nextInt(16)]).join();
    return '${segment(8)}-${segment(4)}-${segment(4)}-${segment(4)}-${segment(12)}';
  }

  String _generateDate() {
    final now = DateTime.now();
    final daysAgo = _random.nextInt(365);
    final date = now.subtract(Duration(days: daysAgo));
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
  }

  String _generateLoremText(FakerLocaleData data) {
    if (data.loremWords.isNotEmpty) {
      final wordCount = _random.nextInt(20) + 5;
      final words = List.generate(
        wordCount,
        (_) => data.loremWords[_random.nextInt(data.loremWords.length)],
      );
      return words.join(' ');
    }
    return 'Lorem ipsum dolor sit amet, consectetur adipiscing elit.';
  }

  String _generateUrl(FakerLocaleData data) {
    final protocols = ['https', 'http'];
    final domains = ['example.com', 'test.com', 'demo.com', 'sample.org'];
    return '${protocols[_random.nextInt(protocols.length)]}://${domains[_random.nextInt(domains.length)]}/path/${_random.nextInt(1000)}';
  }

  String _generateIpAddress() {
    return '${_random.nextInt(256)}.${_random.nextInt(256)}.${_random.nextInt(256)}.${_random.nextInt(256)}';
  }

  String _generateColor() {
    final colors = [
      '#FF5733',
      '#33FF57',
      '#3357FF',
      '#FF33F5',
      '#F5FF33',
      '#33FFF5',
      '#000000',
      '#FFFFFF',
    ];
    return colors[_random.nextInt(colors.length)];
  }

  dynamic _generateDefaultValue(String columnType, int? rowIndex) {
    final type = columnType.toUpperCase();

    if (type.startsWith('INT') ||
        type == 'INTEGER' ||
        type.startsWith('BIGINT') ||
        type.startsWith('SMALLINT') ||
        type.startsWith('TINYINT')) {
      return rowIndex ?? _random.nextInt(100000);
    }

    if (type.startsWith('FLOAT') ||
        type.startsWith('DOUBLE') ||
        type.startsWith('DECIMAL') ||
        type.startsWith('NUMERIC') ||
        type.startsWith('REAL')) {
      return (_random.nextDouble() * 1000).toStringAsFixed(2);
    }

    if (type.startsWith('BOOL') || type.startsWith('BIT')) {
      return _random.nextBool();
    }

    if (type.startsWith('DATE') || type.startsWith('TIME')) {
      return _generateDate();
    }

    if (type.startsWith('JSON') || type.startsWith('JSONB')) {
      return '{"id": ${rowIndex ?? _random.nextInt(1000)}, "value": "${_random.nextInt(100)}"}';
    }

    // Default to string
    return 'value_${rowIndex ?? _random.nextInt(10000)}';
  }

  /// Load locale-specific data
  FakerLocaleData _loadLocaleData(String locale) {
    switch (locale) {
      case 'zh':
        return _zhData;
      case 'de':
        return _deData;
      case 'fr':
        return _frData;
      case 'ru':
        return _ruData;
      default:
        return _enData;
    }
  }
}

/// Semantic type enum
enum SemanticType {
  unknown,
  name,
  email,
  phone,
  address,
  company,
  product,
  orderNumber,
  uuid,
  id,
  age,
  price,
  score,
  date,
  boolean,
  text,
  url,
  ipAddress,
  color,
}

/// Locale-specific faker data
class FakerLocaleData {
  final List<String> firstNames;
  final List<String> lastNames;
  final List<String> cities;
  final List<String> streets;
  final List<String> companies;
  final List<String> products;
  final List<String> loremWords;

  bool get isEmpty =>
      firstNames.isEmpty &&
      lastNames.isEmpty &&
      cities.isEmpty &&
      streets.isEmpty &&
      companies.isEmpty &&
      products.isEmpty &&
      loremWords.isEmpty;

  FakerLocaleData({
    this.firstNames = const [],
    this.lastNames = const [],
    this.cities = const [],
    this.streets = const [],
    this.companies = const [],
    this.products = const [],
    this.loremWords = const [],
  });
}

// English data
final _enData = FakerLocaleData(
  firstNames: [
    'James',
    'Mary',
    'John',
    'Patricia',
    'Robert',
    'Jennifer',
    'Michael',
    'Linda',
    'William',
    'Elizabeth',
    'David',
    'Barbara',
    'Richard',
    'Susan',
    'Joseph',
    'Jessica',
    'Thomas',
    'Sarah',
    'Charles',
    'Karen',
    'Christopher',
    'Nancy',
    'Daniel',
    'Lisa',
    'Matthew',
    'Betty',
    'Anthony',
    'Margaret',
    'Mark',
    'Sandra',
  ],
  lastNames: [
    'Smith',
    'Johnson',
    'Williams',
    'Brown',
    'Jones',
    'Garcia',
    'Miller',
    'Davis',
    'Rodriguez',
    'Martinez',
    'Hernandez',
    'Lopez',
    'Gonzalez',
    'Wilson',
    'Anderson',
    'Thomas',
    'Taylor',
    'Moore',
    'Jackson',
    'Martin',
  ],
  cities: [
    'New York',
    'Los Angeles',
    'Chicago',
    'Houston',
    'Phoenix',
    'Philadelphia',
    'San Antonio',
    'San Diego',
    'Dallas',
    'San Jose',
    'Austin',
    'Jacksonville',
    'Fort Worth',
    'Columbus',
    'Charlotte',
    'San Francisco',
    'Indianapolis',
    'Seattle',
  ],
  streets: [
    'Main St',
    'First Ave',
    'Oak St',
    'Park Ave',
    'Elm St',
    'Maple Ave',
    'Washington St',
    'Lake St',
    'Hill Rd',
    'Church St',
    'King Ave',
    'Miller Dr',
  ],
  companies: [
    'Acme Corporation',
    'Global Tech',
    'Innovate Solutions',
    'Prime Services',
    'Summit Industries',
    'Vertex Systems',
    'Apex Group',
    'Zenith Corp',
    'Pinnacle Tech',
    'Horizon Enterprises',
    'Nova Solutions',
    'Stellar Inc',
  ],
  products: [
    'Wireless Mouse',
    'Mechanical Keyboard',
    'USB-C Hub',
    'Webcam 4K',
    'Bluetooth Speaker',
    'Smart Watch',
    'Noise Canceling Headphones',
    'Portable SSD',
    'Laptop Stand',
    'Monitor Light Bar',
  ],
  loremWords: [
    'lorem',
    'ipsum',
    'dolor',
    'sit',
    'amet',
    'consectetur',
    'adipiscing',
    'elit',
    'sed',
    'do',
    'eiusmod',
    'tempor',
    'incididunt',
    'ut',
    'labore',
    'et',
    'dolore',
    'magna',
    'aliqua',
    'enim',
    'ad',
    'minim',
    'veniam',
    'quis',
    'nostrud',
  ],
);

// Chinese data
final _zhData = FakerLocaleData(
  firstNames: [
    '伟',
    '芳',
    '娜',
    '秀英',
    '敏',
    '静',
    '丽',
    '强',
    '磊',
    '军',
    '洋',
    '勇',
    '艳',
    '杰',
    '娟',
    '涛',
    '明',
    '超',
    '秀兰',
    '霞',
    '平',
    '刚',
    '桂英',
    '文',
    '辉',
    '鑫',
    '宇',
    '博',
    '浩',
    '然',
  ],
  lastNames: [
    '王',
    '李',
    '张',
    '刘',
    '陈',
    '杨',
    '黄',
    '赵',
    '周',
    '吴',
    '徐',
    '孙',
    '马',
    '朱',
    '胡',
    '郭',
    '何',
    '林',
    '罗',
    '高',
    '郑',
    '梁',
    '谢',
    '宋',
    '唐',
    '许',
    '韩',
    '冯',
    '邓',
    '曹',
  ],
  cities: [
    '北京',
    '上海',
    '广州',
    '深圳',
    '杭州',
    '南京',
    '成都',
    '武汉',
    '西安',
    '重庆',
    '天津',
    '苏州',
    '长沙',
    '郑州',
    '东莞',
    '青岛',
    '沈阳',
    '宁波',
  ],
  streets: [
    '中山路',
    '解放路',
    '人民路',
    '建设大街',
    '和平路',
    '新华路',
    '复兴路',
    '朝阳大街',
    '胜利路',
    '前进大街',
    '文化路',
    '工业路',
  ],
  companies: [
    '华为技术有限公司',
    '腾讯科技有限公司',
    '阿里巴巴集团',
    '字节跳动',
    '百度在线网络技术',
    '京东集团',
    '美团点评',
    '滴滴出行',
    '小米科技',
    '网易公司',
    '拼多多',
    '中兴通讯',
  ],
  products: [
    '智能手机',
    '笔记本电脑',
    '无线耳机',
    '智能手表',
    '平板电脑',
    '蓝牙音箱',
    '移动电源',
    '机械键盘',
    '4K显示器',
    '路由器',
  ],
  loremWords: [
    '的',
    '一',
    '是',
    '在',
    '不',
    '了',
    '有',
    '和',
    '人',
    '这',
    '中',
    '大',
    '为',
    '上',
    '个',
    '国',
    '我',
    '以',
    '要',
    '他',
    '时',
    '来',
    '用',
    '们',
    '生',
    '到',
    '作',
    '地',
    '于',
    '出',
  ],
);

// German data
final _deData = FakerLocaleData(
  firstNames: [
    'Max',
    'Alexander',
    'Paul',
    'Ben',
    'Elias',
    'Noah',
    'Louis',
    'Leon',
    'Finn',
    'Luca',
    'Marie',
    'Sophie',
    'Maria',
    'Anna',
    'Emma',
    'Hannah',
    'Mia',
    'Emilia',
    'Lena',
    'Lea',
  ],
  lastNames: [
    'Müller',
    'Schmidt',
    'Schneider',
    'Fischer',
    'Weber',
    'Meyer',
    'Wagner',
    'Becker',
    'Schulz',
    'Hoffmann',
    'Koch',
    'Bauer',
    'Richter',
    'Klein',
    'Wolf',
  ],
  cities: [
    'Berlin',
    'Hamburg',
    'München',
    'Köln',
    'Frankfurt',
    'Stuttgart',
    'Düsseldorf',
    'Leipzig',
    'Dortmund',
    'Essen',
    'Bremen',
    'Dresden',
    'Hannover',
    'Nürnberg',
  ],
  streets: [
    'Hauptstraße',
    'Berliner Straße',
    'Dorfstraße',
    'Bahnhofstraße',
    'Gartenstraße',
    'Bergstraße',
    'Schulstraße',
    'Wiesenweg',
    'Birkenweg',
    'Amselweg',
  ],
  companies: [
    'Siemens AG',
    'BMW Group',
    'Volkswagen AG',
    'Bosch GmbH',
    'SAP SE',
    'Deutsche Telekom',
    'Bayer AG',
    'Adidas AG',
    'Allianz SE',
    'Daimler AG',
  ],
  products: [
    'Auto',
    'Fahrrad',
    'Kühlschrank',
    'Waschmaschine',
    'Staubsauger',
    'Fernseher',
    'Smartphone',
    'Kaffeemaschine',
    'Mikrowelle',
    'Drucker',
  ],
  loremWords: [
    'der',
    'die',
    'und',
    'in',
    'den',
    'von',
    'zu',
    'das',
    'mit',
    'sich',
    'des',
    'auf',
    'für',
    'ist',
    'im',
    'dem',
    'nicht',
    'ein',
    'eine',
    'als',
    'auch',
    'es',
    'an',
    'werden',
  ],
);

// French data
final _frData = FakerLocaleData(
  firstNames: [
    'Jean',
    'Pierre',
    'Michel',
    'André',
    'Philippe',
    'René',
    'Louis',
    'Alain',
    'Jacques',
    'Bernard',
    'Marie',
    'Jeanne',
    'Françoise',
    'Monique',
    'Catherine',
    'Nathalie',
    'Isabelle',
    'Sophie',
    'Christine',
    'Anne',
  ],
  lastNames: [
    'Martin',
    'Bernard',
    'Thomas',
    'Petit',
    'Robert',
    'Richard',
    'Durand',
    'Dubois',
    'Moreau',
    'Laurent',
    'Simon',
    'Michel',
    'Lefèvre',
    'Leroy',
    'Roux',
    'David',
    'Bertrand',
    'Morel',
    'Fournier',
    'Girard',
  ],
  cities: [
    'Paris',
    'Marseille',
    'Lyon',
    'Toulouse',
    'Nice',
    'Nantes',
    'Strasbourg',
    'Montpellier',
    'Bordeaux',
    'Lille',
    'Rennes',
    'Reims',
    'Le Havre',
    'Saint-Étienne',
    'Toulon',
  ],
  streets: [
    'Rue de la Paix',
    'Avenue des Champs-Élysées',
    'Boulevard Saint-Germain',
    'Rue de Rivoli',
    'Avenue Montaigne',
    'Rue du Faubourg Saint-Honoré',
    'Place de la Concorde',
    'Rue de la République',
    'Avenue de l\'Opéra',
  ],
  companies: [
    'L\'Oréal',
    'TotalEnergies',
    'Sanofi',
    'AXA',
    'BNP Paribas',
    'Carrefour',
    'Airbus',
    'Schneider Electric',
    'Vinci',
    'Danone',
  ],
  products: [
    'Parfum',
    'Vin',
    'Fromage',
    'Baguette',
    'Croissant',
    'Tarte',
    'Confiture',
    'Champagne',
    'Café',
    'Chocolat',
  ],
  loremWords: [
    'le',
    'de',
    'et',
    'à',
    'un',
    'il',
    'être',
    'et',
    'en',
    'avoir',
    'que',
    'pour',
    'dans',
    'ce',
    'son',
    'une',
    'sur',
    'avec',
    'ne',
    'se',
    'au',
    'plus',
    'par',
  ],
);

// Russian data
final _ruData = FakerLocaleData(
  firstNames: [
    'Александр',
    'Дмитрий',
    'Максим',
    'Сергей',
    'Андрей',
    'Алексей',
    'Артём',
    'Илья',
    'Кирилл',
    'Михаил',
    'Никита',
    'Матвей',
    'Роман',
    'Егор',
    'Арсений',
    'Мария',
    'Анна',
    'Алина',
    'Елена',
    'Ольга',
    'Наталья',
    'Ирина',
    'Татьяна',
    'Светлана',
    'Екатерина',
    'Анастасия',
    'Виктория',
    'Валерия',
    'Полина',
    'Дарья',
  ],
  lastNames: [
    'Иванов',
    'Смирнов',
    'Кузнецов',
    'Попов',
    'Васильев',
    'Петров',
    'Соколов',
    'Михайлов',
    'Новиков',
    'Федоров',
    'Морозов',
    'Волков',
    'Алексеев',
    'Лебедев',
    'Семенов',
  ],
  cities: [
    'Москва',
    'Санкт-Петербург',
    'Новосибирск',
    'Екатеринбург',
    'Казань',
    'Нижний Новгород',
    'Челябинск',
    'Самара',
    'Омск',
    'Ростов-на-Дону',
    'Уфа',
    'Красноярск',
    'Воронеж',
    'Пермь',
    'Волгоград',
  ],
  streets: [
    'Ленина',
    'Гагарина',
    'Кирова',
    'Мира',
    'Советская',
    'Победы',
    'Школьная',
    'Набережная',
    'Лесная',
    'Садовая',
    'Центральная',
    'Молодёжная',
  ],
  companies: [
    'Газпром',
    'Лукойл',
    'Роснефть',
    'Сбербанк',
    'ВТБ',
    'Ростех',
    'Транснефть',
    'РЖД',
    'Аэрофлот',
    'Яндекс',
  ],
  products: [
    'Матрёшка',
    'Самовар',
    'Валенки',
    'Шапка-ушанка',
    'Павловопосадский платок',
    'Хохлома',
    'Гжель',
    'Красная икра',
    'Чёрная икра',
    'Водка',
  ],
  loremWords: [
    'в',
    'и',
    'не',
    'на',
    'я',
    'быть',
    'он',
    'с',
    'что',
    'а',
    'по',
    'это',
    'она',
    'к',
    'но',
    'мы',
    'как',
    'из',
    'у',
    'то',
    'за',
    'свой',
    'ее',
    'очень',
  ],
);
