import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/paginated_result_service.dart';

void main() {
  group('PaginatedResultService', () {
    test('should initialize with empty data', () {
      final service = PaginatedResultService();
      expect(service.totalRows, 0);
      expect(service.totalPages, 0);
      expect(service.currentPage, 0);
    });

    test('should set data and calculate pages', () {
      final service = PaginatedResultService();
      final data = List.generate(250, (i) => {'id': i, 'value': 'test$i'});

      service.setData(data);

      expect(service.totalRows, 250);
      expect(service.totalPages, 3); // 250 / 100 = 3 pages
      expect(service.currentPage, 1);
    });

    test('should return first page data', () {
      final service = PaginatedResultService();
      final data = List.generate(150, (i) => {'id': i, 'value': 'test$i'});
      service.setData(data);

      final pageData = service.currentPageData;

      expect(pageData.length, 100);
      expect(pageData.first['id'], 0);
      expect(pageData.last['id'], 99);
    });

    test('should navigate to next page', () {
      final service = PaginatedResultService();
      final data = List.generate(250, (i) => {'id': i, 'value': 'test$i'});
      service.setData(data);

      service.nextPage();

      expect(service.currentPage, 2);
      expect(service.currentPageData.first['id'], 100);
    });

    test('should navigate to previous page', () {
      final service = PaginatedResultService();
      final data = List.generate(250, (i) => {'id': i, 'value': 'test$i'});
      service.setData(data);
      service.nextPage();

      service.previousPage();

      expect(service.currentPage, 1);
    });

    test('should go to specific page', () {
      final service = PaginatedResultService();
      final data = List.generate(250, (i) => {'id': i, 'value': 'test$i'});
      service.setData(data);

      service.goToPage(2);

      expect(service.currentPage, 2);
    });

    test('should not go beyond page boundaries', () {
      final service = PaginatedResultService();
      final data = List.generate(100, (i) => {'id': i, 'value': 'test$i'});
      service.setData(data);

      service.nextPage(); // Try to go beyond first page
      expect(service.currentPage, 1);

      service.previousPage(); // Try to go before first page
      expect(service.currentPage, 1);
    });
  });
}
