import * as s from '../../../../../src/core/viz/functions';

describe('src/core/viz/expressions/viewportAggregation', () => {
    const $price = s.property('price');
    describe('global filtering', () => {
        const fakeMetadata = {
            columns: [{
                type: 'number',
                name: 'price',
                min: 0,
                avg: 1,
                max: 2,
                sum: 3,
                count: 4,

            }],
        };
        it('globalMin($price) should return the metadata min', () => {
            const globalMin = s.globalMin($price);
            globalMin._compile(fakeMetadata);
            expect(globalMin.eval()).toEqual(0);
        });

        it('globalAvg($price) should return the metadata avg', () => {
            const globalAvg = s.globalAvg($price);
            globalAvg._compile(fakeMetadata);
            expect(globalAvg.eval()).toEqual(1);
        });

        it('globalMax($price) should return the metadata max', () => {
            const globalMax = s.globalMax($price);
            globalMax._compile(fakeMetadata);
            expect(globalMax.eval()).toEqual(2);
        });

        it('globalSum($price) should return the metadata sum', () => {
            const globalSum = s.globalSum($price);
            globalSum._compile(fakeMetadata);
            expect(globalSum.eval()).toEqual(3);
        });

        it('globalCount($price) should return the metadata count', () => {
            const globalCount = s.globalCount($price);
            globalCount._compile(fakeMetadata);
            expect(globalCount.eval()).toEqual(4);
        });

        it('globalPercentile($price, 30) should return the metadata count', () => {
            fakeMetadata.sample = [];
            for (let i = 0; i <= 1000; i++) {
                fakeMetadata.sample.push({
                    'price': i / 1000 * (fakeMetadata.columns[0].max - fakeMetadata.columns[0].min) + fakeMetadata.columns[0].min,
                });
            }
            const globalPercentile = s.globalPercentile($price, 30);
            globalPercentile._compile(fakeMetadata);
            expect(globalPercentile.eval()).toBeCloseTo(0.3 * (fakeMetadata.columns[0].max - fakeMetadata.columns[0].min) + fakeMetadata.columns[0].min, 2);
        });
    });

    fdescribe('viewport filtering', () => {
        let fakeGl = jasmine.createSpyObj('fakeGl', ['uniform1f']);
        function fakeDrawMetadata(expr) {
            expr._resetViewportAgg({ price: 0 });
            expr._accumViewportAgg({ price: 0 });
            expr._accumViewportAgg({ price: 0.5 });
            expr._accumViewportAgg({ price: 1.5 });
            expr._accumViewportAgg({ price: 2 });
            expr._preDraw(null, null, fakeGl);
        }
        it('viewportMin($price) should return the metadata min', () => {
            const viewportMin = s.viewportMin($price);
            fakeDrawMetadata(viewportMin);
            expect(viewportMin.eval()).toEqual(0);
        });

        it('viewportAvg($price) should return the metadata avg', () => {
            const viewportAvg = s.viewportAvg($price);
            fakeDrawMetadata(viewportAvg);
            expect(viewportAvg.eval()).toEqual(1);
        });

        it('viewportMax($price) should return the metadata max', () => {
            const viewportMax = s.viewportMax($price);
            fakeDrawMetadata(viewportMax);
            expect(viewportMax.eval()).toEqual(2);
        });

        it('viewportSum($price) should return the metadata sum', () => {
            const viewportSum = s.viewportSum($price);
            fakeDrawMetadata(viewportSum);
            expect(viewportSum.eval()).toEqual(4);
        });

        it('viewportCount($price) should return the metadata count', () => {
            const viewportCount = s.viewportCount($price);
            fakeDrawMetadata(viewportCount);
            expect(viewportCount.eval()).toEqual(4);
        });

        it('viewportPercentile($price) should return the metadata count', () => {
            fakeDrawMetadata.columns[0].accumHistogram = [];
            fakeDrawMetadata.columns[0].histogramBuckets = 1000;
            for (let i = 0; i < 1000; i++) {
                fakeDrawMetadata.columns[0].accumHistogram[i] = i + 1;
            }
            const viewportPercentile = s.viewportPercentile($price, 30);
            viewportPercentile._preDraw(null, fakeDrawMetadata, fakeGl);
            expect(viewportPercentile.eval()).toBeCloseTo(0.3 * (fakeDrawMetadata.columns[0].max - fakeDrawMetadata.columns[0].min) + fakeDrawMetadata.columns[0].min, 2);
        });
    });
});
